// Servico de administracao da Arena -- e' o "load-rom.sh" via HTTP, pra
// o gamo-api poder acionar sem precisar de SSH manual. So' quem tem o
// segredo de servidor-a-servidor (ARENA_ADMIN_SECRET) pode chamar --
// nunca e' exposto pro navegador do jogador nem do organizador.
//
// Precisa do socket do Docker montado (/var/run/docker.sock) e do MESMO
// caminho /opt/arena montado dentro deste container -- assim os paths
// relativos do docker-compose.yml (./assets/cores etc.) resolvem certo
// quando o daemon do host executa os comandos.

const express = require("express");
const multer = require("multer");
const JSZip = require("jszip");
const { spawn } = require("child_process");
const path = require("path");

const SECRET = process.env.ARENA_ADMIN_SECRET;
const PORT = process.env.PORT || 8082;
const ARENA_DIR = "/opt/arena";

if (!SECRET) {
  console.error("ARENA_ADMIN_SECRET nao configurado -- abortando");
  process.exit(1);
}

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 800 * 1024 * 1024 } });

// /health fica ANTES do middleware de auth de propósito -- é o que o
// gamo-api usa pra saber se a arena já está de pé, sem precisar do segredo.
app.get("/health", (req, res) => res.json({ ok: true }));

app.use((req, res, next) => {
  const auth = req.headers.authorization || "";
  if (auth !== `Bearer ${SECRET}`) {
    return res.status(401).json({ ok: false, error: "unauthorized" });
  }
  next();
});

// Roda um comando e resolve/rejeita no fim. Nunca inclui entrada do
// usuario diretamente na string do comando -- args sempre em array.
function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    console.log(`[run] ${cmd} ${args.join(" ")}`);
    const child = spawn(cmd, args, { cwd: ARENA_DIR, ...opts });
    let out = "",
      err = "";
    child.stdout?.on("data", (d) => (out += d));
    child.stderr?.on("data", (d) => (err += d));
    child.on("close", (code) => {
      if (code === 0) resolve({ out, err });
      else reject(new Error(`${cmd} saiu com codigo ${code}: ${err || out}`));
    });
    child.on("error", reject);
  });
}

// Copia o buffer da ROM pro tmpfs do container via pipe (docker cp NAO
// funciona com destino em tmpfs nessa versao do Docker -- ver README.md).
function pipeIntoContainer(buffer, destPath) {
  return new Promise((resolve, reject) => {
    const child = spawn("docker", [
      "exec",
      "-i",
      "cloud-game-local",
      "sh",
      "-c",
      `cat > ${destPath}`,
    ]);
    let err = "";
    child.stderr?.on("data", (d) => (err += d));
    child.on("close", (code) =>
      code === 0 ? resolve() : reject(new Error(err || `exit ${code}`)),
    );
    child.on("error", reject);
    child.stdin.write(buffer);
    child.stdin.end();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Junta QUALQUER sequência de caracteres especiais num único "_" (nunca
// vários underscores em fileira). Isso importa porque o próprio CloudRetro
// usa "___" (triplo) como separador entre o hash da sala e o nome do jogo
// (pkg/games/launcher.go) -- um nome como "Killer Instinct Gold (USA) (Rev
// A).n64" tem duas tags entre parênteses coladas, e sanitizar char-a-char
// (1 "_" por caractere) gera "___" por coincidência bem no meio do nome.
// Isso faz o CloudRetro cortar o nome do jogo errado (usa só a primeira
// metade) quando um SEGUNDO jogador entra na sala -- ele carrega som mas
// nunca o vídeo, preso num loop de reconexão que falha sempre com
// "couldn't find game info for the game ...". Bug real corrigido em
// 2026-08-19 (reproduzido com N64/Killer Instinct Gold, mesma causa provável
// do caso anterior com SNES).
function sanitizeName(name) {
  return name.replace(/[^a-zA-Z0-9._-]+/g, "_");
}

// Plataformas que precisam de mais de 1 arquivo (ou de uma subpasta
// específica) -- espelha os `folder:` do config.yaml (pkg/config).
// "" (vazio/ausente) = pasta raiz, onde vivem SNES/Mega Drive/N64/GBA/NES.
const PLATFORM_FOLDERS = new Set(["psx", "mame", "dos", "dc"]);

// Flycast procura BIOS em libretro/system/dc/ (não em assets/games).
const DREAMCAST_BIOS_FILES = new Set(["dc_boot.bin", "dc_flash.bin"]);
const LIBRETRO_SYSTEM_DC_DIR = "/usr/local/share/cloud-game/libretro/system/dc";

// Arcade/Neo Geo (FBNeo) exige romset em .zip -- isso é do próprio núcleo,
// não uma escolha nossa. Em vez de pedir pro organizador montar o zip (e
// arriscar subpasta interna, que quebra o FBNeo), a gente monta aqui,
// sempre no nível raiz do zip, 100% em memória -- nunca toca disco, nem no
// container do admin-server nem em lugar algum (mesma garantia do resto
// da Arena).
async function zipFilesFlat(files) {
  const zip = new JSZip();
  for (const f of files) {
    const safeName = sanitizeName(path.basename(f.originalname));
    zip.file(safeName, f.buffer);
  }
  // STORE (sem compressão): ROMs já são dados binários densos, comprimir
  // ganha pouco e custa tempo -- aqui velocidade importa mais.
  return zip.generateAsync({ type: "nodebuffer", compression: "STORE" });
}

// O .cue referencia o(s) .bin pelo nome exato (texto puro, ex.:
// `FILE "Tekken 3 (USA) (Track 1).bin" BINARY`). Como os nomes de arquivo
// são sanitizados abaixo (espaço/parênteses viram "_") antes de irem pro
// tmpfs, o .cue precisa ser reescrito com os MESMOS nomes sanitizados --
// senão o core (pcsx_rearmed) procura um arquivo que não existe com aquele
// nome e trava carregando pra sempre, sem erro nenhum (bug real: Tekken 3,
// 2026-08-19). Faz um replace de texto puro (sem regex) pra não precisar
// escapar caracteres especiais do nome original.
function rewriteCueReferences(files, nameMap) {
  return files.map((f) => {
    if (!/\.cue$/i.test(f.originalname)) return f;
    let text = f.buffer.toString("utf8");
    for (const [original, safe] of nameMap) {
      if (original === f.originalname || original === safe) continue;
      text = text.split(original).join(safe);
    }
    return { ...f, buffer: Buffer.from(text, "utf8") };
  });
}

// 64: romsets grandes passam de 32 arquivos fácil -- CPS-3 (ex.: Street
// Fighter III) costuma vir com as SIMMs divididas em muitos chips pequenos.
// Bug real corrigido em 2026-08-19: 32 estourava com "Unexpected field" (erro
// genérico do multer quando o maxCount do campo é excedido -- não vem com
// mensagem clara de "arquivos demais") ao tentar enviar um SFIII. Precisa
// bater com o mesmo limite em arena.routes.ts (gamo-api) -- o arquivo passa
// pelos dois multers em sequência.
app.post("/create-match", upload.array("roms", 64), async (req, res) => {
  try {
    if (!req.files || req.files.length === 0) throw new Error("nenhum arquivo de ROM enviado");

    const matchId = req.body.matchId || "sem-id";
    const platformFolder = PLATFORM_FOLDERS.has(req.body.platformFolder)
      ? req.body.platformFolder
      : null;
    const gamesDir = platformFolder
      ? `/usr/local/share/cloud-game/assets/games/${platformFolder}`
      : "/usr/local/share/cloud-game/assets/games";

    const nameMap = req.files.map((f) => [
      f.originalname,
      sanitizeName(path.basename(f.originalname)),
    ]);
    const safeNames = nameMap.map(([, safe]) => safe);
    const files = rewriteCueReferences(req.files, nameMap);

    // Arcade/Neo Geo exige que o .zip final se chame exatamente como o
    // romset do FBNeo (ex.: "kof97.zip") -- é assim que o core reconhece
    // qual jogo é. matchId é só um rótulo livre de sessão/histórico (pode
    // vir vazio/aleatório), então não serve pra isso -- exigimos romName à
    // parte (validado como obrigatório em arena.schema.ts quando
    // platformFolder === "mame"). Bug real corrigido em 2026-08-19: o zip
    // era nomeado com o matchId (ex.: "97.zip"), que o FBNeo rejeitava como
    // "Romset is unknown" por não bater com nenhum driver conhecido.
    const romName = req.body.romName;
    if (platformFolder === "mame" && !romName) {
      throw new Error(
        "romName é obrigatório para Arcade/Neo Geo (nome exato do romset, ex.: kof97)",
      );
    }

    console.log(
      `[create-match] matchId=${matchId} folder=${platformFolder || "(raiz)"} romName=${romName || "-"} arquivos=${safeNames.join(", ")}`,
    );

    // Reseta so' os servicos do jogo (nunca este proprio servico -- senao
    // ele se mataria no meio do request).
    await run("docker", ["compose", "stop", "cloud-game", "arena-auth", "xvfb"]);
    await run("docker", ["compose", "rm", "-f", "cloud-game", "arena-auth", "xvfb"]);
    await run("docker", ["compose", "up", "-d", "cloud-game", "arena-auth", "xvfb"]);

    await sleep(3000);

    // A subpasta (quando existe) precisa estar criada e com TODOS os
    // arquivos dentro ANTES do worker iniciar (gate do .rom-ready) -- o
    // watcher de arquivos do CloudRetro não é recursivo, então só o scan
    // inicial (sincrono, no boot do worker) vê o que está dentro de uma
    // subpasta corretamente. Ver infra/arena/README.md.
    if (platformFolder) {
      await run("docker", ["exec", "cloud-game-local", "mkdir", "-p", gamesDir]);
    }
    if (platformFolder === "dc") {
      await run("docker", ["exec", "cloud-game-local", "mkdir", "-p", LIBRETRO_SYSTEM_DC_DIR]);
    }

    if (platformFolder === "mame") {
      // FBNeo exige .zip -- monta aqui (sempre plano, sem subpasta) em vez
      // de depender do organizador zipar certo do lado dele. O nome do zip
      // é o romName (nome do romset), NUNCA o matchId -- ver comentário acima.
      const safeRomName = sanitizeName(romName);
      const zipBuffer = await zipFilesFlat(files);
      await pipeIntoContainer(zipBuffer, `${gamesDir}/${safeRomName}.zip`);
    } else {
      for (let i = 0; i < files.length; i++) {
        const destDir =
          platformFolder === "dc" && DREAMCAST_BIOS_FILES.has(safeNames[i].toLowerCase())
            ? LIBRETRO_SYSTEM_DC_DIR
            : gamesDir;
        await pipeIntoContainer(files[i].buffer, `${destDir}/${safeNames[i]}`);
      }
    }
    await run("docker", ["exec", "cloud-game-local", "touch", "/tmp/.rom-ready"]);

    console.log(`[create-match] OK matchId=${matchId}`);
    res.json({ ok: true, matchId, roms: safeNames });
  } catch (err) {
    console.error("[create-match] falhou:", err.message);
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.listen(PORT, () => console.log(`arena-admin-server ouvindo na porta ${PORT}`));
