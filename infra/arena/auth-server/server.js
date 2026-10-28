// Servico minimo que valida o token de handoff emitido pelo gamo-api, e
// guarda em memoria o mapa matchId -> roomId (o roomId real e gerado pelo
// proprio CloudRetro quando o host inicia o jogo -- nao pode ser inventado
// pelo cliente, ver infra/arena/README.md).
//
// Fluxo: quem tem role=staff e' sempre o "host" -- inicia o jogo direto e
// reporta o roomId aqui (POST /report-room). Quem tem role=player espera
// (poll no GET /verify) até o roomId aparecer, e ai entra na MESMA sala.

const http = require("http");
const jwt = require("jsonwebtoken");
const { URL } = require("url");

const SECRET = process.env.ARENA_JWT_SECRET;
const PORT = process.env.PORT || 8081;

if (!SECRET) {
  console.error("ARENA_JWT_SECRET nao configurado -- abortando");
  process.exit(1);
}

// matchId -> roomId. Zera sozinho quando o container reinicia (é o que
// queremos -- cada partida nova começa com o registro limpo).
const roomByMatch = new Map();

// matchId -> {w,h,a,s,flip,rot} (info de vídeo do CloudRetro). O
// coordinator manda essa info via um broadcast único (na primeira vez que
// o core carrega o vídeo) que só alcança quem já estava conectado NAQUELE
// momento -- ou seja, só o staff, que cria a sala antes de qualquer
// jogador entrar. Jogadores que entram depois nunca recebem isso do
// próprio CloudRetro (bug real descoberto em teste ao vivo, 2026-08-21).
// O staff reencaminha aqui assim que recebe, e o jogador busca no
// /verify -- não depende mais do timing do broadcast do CloudRetro.
const avByMatch = new Map();

const cors = (res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
};

const readBody = (req) =>
  new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });

const verifyToken = (token) =>
  jwt.verify(token, SECRET, { issuer: "gamo-api", audience: "arena.gamo.games" });

http
  .createServer(async (req, res) => {
    cors(res);

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url, `http://${req.headers.host}`);

    if (req.method === "GET" && url.pathname === "/verify") {
      const token = url.searchParams.get("token");
      if (!token) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ valid: false, error: "missing token" }));
        return;
      }
      try {
        const payload = verifyToken(token);
        const roomId = roomByMatch.get(String(payload.matchId)) || null;
        const av = avByMatch.get(String(payload.matchId)) || null;
        console.log(
          `[verify] OK matchId=${payload.matchId} slot=${payload.slot} role=${payload.role} roomId=${roomId} av=${JSON.stringify(av)}`,
        );
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            valid: true,
            sub: payload.sub,
            matchId: payload.matchId,
            slot: payload.slot,
            role: payload.role,
            nickname: payload.nickname,
            roomId,
            av,
          }),
        );
      } catch (err) {
        console.log(`[verify] REJEITADO: ${err.message}`);
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ valid: false, error: err.message }));
      }
      return;
    }

    if (req.method === "POST" && url.pathname === "/report-room") {
      try {
        const body = JSON.parse(await readBody(req));
        const payload = verifyToken(body.token);
        if (payload.role !== "staff") {
          throw new Error("apenas staff pode reportar sala");
        }
        if (String(payload.matchId) !== String(body.matchId)) {
          throw new Error("matchId nao corresponde ao token");
        }
        if (body.roomId !== undefined && body.roomId !== null) {
          roomByMatch.set(String(body.matchId), String(body.roomId));
          console.log(`[report-room] matchId=${body.matchId} -> roomId=${body.roomId}`);
        }
        if (body.av !== undefined && body.av !== null) {
          avByMatch.set(String(body.matchId), body.av);
          console.log(`[report-room] matchId=${body.matchId} av=${JSON.stringify(body.av)}`);
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true }));
      } catch (err) {
        console.log(`[report-room] REJEITADO: ${err.message}`);
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: false, error: err.message }));
      }
      return;
    }

    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not found" }));
  })
  .listen(PORT, () => console.log(`arena-auth-server ouvindo na porta ${PORT}`));
