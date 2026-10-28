# Arena Retrogame — Protótipo (Fase de avaliação)

Objetivo desta fase: validar, num servidor de teste real na Vultr, se dá pra
rodar um emulador de SNES/Mega Drive na nuvem e jogar via navegador com
vídeo por WebRTC — sem guardar ROM em disco persistente. Ainda não é a
integração com o gamo-web (isso vem depois, se o protótipo validar).

Ferramenta escolhida: **CloudRetro** (github.com/giongto35/cloud-game) —
open source, self-hostable via Docker, suporta libretro (SNES, GBA, N64,
MAME, DOS...) e já tem modo "Online Multiplayer" nativo.

**Aviso honesto**: a documentação pública desse projeto tem lacunas (a wiki
está marcada como desatualizada) e o autor original reduziu a manutenção
pra focar num projeto mais genérico (CloudMorph). Ele continua funcional e
buildável via Docker, mas isso significa que vamos precisar ler o código
real e talvez ajustar coisas na mão — não vai ser 100% "seguir a receita".
Por isso este protótipo é sobre aprender rápido e barato antes de investir
mais.

---

## Fase 1 — Criar a instância (agora automatizado)

**Caminho rápido (recomendado):** com `infra/arena/.env` preenchido
(`VULTR_API_KEY=...`, nunca comitar), rode:

```
cd infra/arena
./up.sh
```

Isso cria a instância (São Paulo, plano `voc-c-2c-4gb-50s`, Ubuntu 26.04 LTS,
sua chave SSH já cadastrada), espera ficar pronta, roda o `bootstrap.sh`,
clona o CloudRetro, aplica o `docker-compose.yml` com tmpfs e abre o
firewall — tudo em ~3-5 minutos, sem clicar em nada. O IP final é impresso
no fim e salvo em `.last-instance-id` (usado pelo `down.sh`).

Pra derrubar: `./down.sh --yes` (destrói de verdade, para a cobrança).

<details>
<summary>Caminho manual (só se o up.sh falhar ou você quiser entender o passo a passo)</summary>

1. No painel da Vultr, **Quick Deploy → Instances**.
2. **Dedicated CPU** → categoria **CPU Optimized** (não "VX1" — essa linha
   não tem disponibilidade em São Paulo).
3. **Location**: São Paulo, BR.
4. **Plan**: `voc-c-2c-4gb-50s` (2 vCPU / 4GB / 50GB NVMe).
5. **OS**: Ubuntu 26.04 LTS x64.
6. SSH key já cadastrada (nome "Arena gamo"), hostname/label à sua escolha.
7. Desligue Automatic Backups e DDoS Protection (custo extra sem necessidade).
8. Deploy Now, espere "Running", anote o IP.

> Custo: lembre de **destruir a instância** (não só desligar) quando
> terminar o teste do dia — Vultr cobra por hora enquanto ela existir,
> mesmo desligada, a não ser que seja realmente deletada.

</details>

## Fase 2 — Primeiro acesso e preparo do servidor

Do seu terminal (PowerShell ou Git Bash):

```
ssh root@<IP_DA_INSTANCIA>
```

Uma vez dentro, copie o conteúdo de `infra/arena/bootstrap.sh` (deste
repositório) pro servidor e rode:

```
sudo bash bootstrap.sh
```

Isso instala Docker, desliga swap (importante pra garantia de "ROM só em
RAM", ver seção abaixo), configura firewall básico e instala o Caddy
(proxy reverso com HTTPS automático).

## Fase 3 — Domínio + TLS (implementado, DNS automático)

`arena.gamo.games` é servido com HTTPS de verdade via Caddy (`./Caddyfile`),
que o `up.sh`/o provisionamento automático via gamo-api já instalam e
recarregam a cada deploy. Como a instância é sob demanda (o IP muda toda
vez que a arena liga), **o registro A é atualizado automaticamente via API
da Cloudflare** (provedor real do `gamo.games`) logo que o IP novo é
conhecido — sem isso, seria preciso reapontar o DNS à mão a cada partida.

Configuração (uma vez só):
1. Na Cloudflare, **My Profile → API Tokens → Create Token → template
   "Edit zone DNS"**, escopado só pra zone `gamo.games` (nunca "All zones").
2. Cole o token em `CLOUDFLARE_API_TOKEN` no `.env` deste diretório (pro
   `up.sh`) e em `gamo-api/.env`/Railway (pro botão "Ligar Arena" do
   gamo-admin) — **nunca comitar**.
3. Pronto. Sem o token configurado, o `up.sh` ainda funciona, só que imprime
   o IP no final pra você apontar o DNS na mão (fallback).

Blast radius do token: escopado só à zone `gamo.games`, só permissão de
editar registros DNS — não dá acesso a mais nada da conta Cloudflare.

Rede de segurança mesmo com a automação: `GET /api/arena/server/status`
sempre faz uma resolução DNS real e devolve `domainReady`; o gamo-admin
mostra um aviso e **bloqueia a criação de partida** enquanto `domainReady`
for `false` (ex.: a automação falhou, ou o DNS ainda está propagando) --
pra nunca gerar um link que não vai funcionar.

**Importante se algum dia mexer no registro manualmente:** deixe-o em
"DNS only" (nuvem cinza, sem proxy) — o desafio HTTP-01 do Let's Encrypt e
o WebRTC precisam alcançar o IP real da Vultr direto, um proxy CDN na
frente quebra os dois (é por isso que a automação já cria o registro com
`proxied: false`).

Só `arena.gamo.games` (porta 443, servida pelo Caddy) e
`arena.gamo.games:8081` (arena-auth, chamado direto pelo navegador do
jogador — por isso precisa de TLS de verdade também, não só a 443) ficam
por trás do Caddy. `arena-admin` (porta 8082) continua em HTTP puro direto
no IP — só o gamo-api fala com ele, servidor-a-servidor, nunca um
navegador, então não tem problema de conteúdo misto nem depende do DNS.

**Bug real corrigido em 2026-08-19 -- limite semanal da Let's Encrypt
esgotado.** Como a VM é destruída e recriada do zero a cada
"Desligar"/"Ligar" (custo real só enquanto está ligada), o Caddy pedia um
certificado TLS **novo** pro mesmo `arena.gamo.games` em toda sessão de
teste -- e a Let's Encrypt limita a **5 emissões por hostname a cada 7
dias**. Depois de vários religamentos no mesmo dia, o limite esgotou e o
Caddy passou a rejeitar TODA conexão HTTPS (handshake TLS falha com
"internal_error" -- confirmado via `openssl s_client`), até liberar de
novo (retry-after informado no log do próprio Caddy,
`journalctl -u caddy`). Corrigido: `arenaServer.service.ts` agora guarda o
diretório de dados do Caddy (`/var/lib/caddy/.local/share/caddy` --
conta ACME + certificados emitidos, compactado e em base64) no Postgres a
cada "Desligar" (`backupCaddyCerts`) e restaura antes do primeiro reload
do Caddy no próximo "Ligar" (`restoreCaddyCerts`) -- assim o mesmo
certificado sobrevive entre sessões, e só pedimos um novo perto da
validade real (a Let's Encrypt já renova automaticamente a partir de ~60
dos 90 dias de validade), não mais uma vez por teste.

## Fase 4 — Rodar o CloudRetro (fazemos juntos, ao vivo)

Esta parte eu não vou pré-escrever aqui com comandos exatos, de propósito:
o `docker-compose.yml` real do projeto (portas, volumes, nomes de serviço)
precisa ser lido direto do repositório no momento em que formos rodar,
porque:
- a documentação pública tem lacunas, então detalhes importantes (ex:
  exatamente como a ROM é referenciada por um core) só ficam claros
  olhando `pkg/config/config.yaml` e o `docker-compose.yml` reais;
- eu não quero te dar um arquivo "reconstruído de memória" que pareça
  pronto mas tenha um detalhe errado e te faça perder tempo depurando.

Quando a instância estiver no ar e você tiver rodado o `bootstrap.sh`, me
chama de volta que a gente clona o repo real dentro de `/opt/arena` e
ajusta o `docker-compose.yml` juntos — com uma mudança central já decidida:
**a pasta de ROMs vai ser montada como `tmpfs` (RAM), nunca como pasta em
disco**, usando a opção nativa do Docker Compose (`tmpfs:` no serviço), não
um bind-mount de diretório real. Isso é mais simples e mais seguro do que
gerenciar um mount de tmpfs manual no host.

## Fase 5 — Carregar uma ROM na sessão ativa (validado 2026-08-18)

**Regra descoberta na prática, importante não esquecer:** o CloudRetro só
detecta arquivo novo automaticamente (sem precisar reiniciar o container)
se o arquivo for colocado **direto na raiz de `assets/games`**, sem
subpasta por plataforma. Isso acontece porque o watcher de arquivos do
projeto (`pkg/games/library.go`, função `watch()`) só observa a pasta de
primeiro nível — criar uma subpasta (`assets/games/nes/`) dispara um scan
cedo demais, antes do arquivo dentro dela existir, e escrever dentro de uma
subpasta já existente não dispara scan nenhum (fsnotify não é recursivo
aqui). Colocar o arquivo direto em `assets/games/rom.nes` funciona, porque
é exatamente a pasta observada.

Requisitos pra isso funcionar:
- `CLOUD_GAME_LIBRARY_WATCHMODE=true` no `environment:` do serviço
  `cloud-game` (já está no `docker-compose.yml` deste repositório).
- `docker cp` **não funciona** pra destino em tmpfs nessa versão do Docker
  (erro "Can't add file ... to tar: io: read/write on closed pipe" /
  "Could not find the file ... in container"). Use pipe via `docker exec`
  em vez disso:
  ```
  cat "/caminho/local/do/jogo.nes" | docker exec -i cloud-game-local sh -c \
    'cat > /usr/local/share/cloud-game/assets/games/rom.nes'
  ```
- **Nunca use `docker restart`** depois de carregar a ROM — o tmpfs é
  remontado vazio nesse ciclo (confirmado: o arquivo desaparece). Só reinicie
  se quiser mesmo limpar a sessão (é literalmente o comportamento que
  queremos entre partidas — cada `docker compose up -d`/restart = ROM
  anterior garantidamente apagada).
- **A descoberta mais importante do dia**: o *coordinator* só recebe a
  lista de jogos do *worker* **uma única vez**, no handshake inicial de
  quando o worker liga. Se a ROM for copiada pro tmpfs **depois** desse
  handshake, o coordinator nunca fica sabendo — e isso quebra o frontend
  de um jeito que **não é resolvido limpando cache/trocando de navegador**
  (`gameList.js`: `list[index].title` quebra com lista vazia — é bug de
  estado do servidor, não do cliente). A correção: o comando do serviço
  `cloud-game` no `docker-compose.yml` faz o `./worker` esperar um arquivo
  de sinal (`/tmp/.rom-ready`) antes de iniciar. Fluxo correto pra carregar
  uma partida nova:
  ```
  docker compose up -d                      # tmpfs limpo, worker ainda não iniciou
  # copiar a(s) ROM(s) via pipe (ver acima) pra assets/games/ (raiz, sem subpasta)
  docker exec cloud-game-local touch /tmp/.rom-ready   # libera o worker pra iniciar
  ```
  Isso também é o comportamento certo pra produção: o "console" só liga
  depois que o jogo da partida já está carregado, nunca antes.

## Consoles com mais de 1 arquivo (PS1, Arcade/Neo Geo, DOS)

SNES/Mega Drive/N64/GBA/NES são sempre 1 arquivo na raiz de `assets/games`.
Outros consoles esperam mais de 1 arquivo E numa subpasta própria (o
`folder:` de cada entrada no `pkg/config/config.yaml`):

- **PS1** (`pcsx_rearmed`, pasta `psx`): o `.cue` referencia o(s) `.bin`
  pelo nome exato -- precisa dos dois (ou um `.chd` sozinho, formato que
  não tem esse problema). Testado com sucesso em 2026-08-19 (mas com um
  ROM de nome já "limpo" -- ver bug abaixo).
  **Bug real corrigido em 2026-08-19**: o admin-server sanitiza todo nome
  de arquivo (espaço/parênteses viram `_`) antes de gravar no tmpfs, mas
  não reescrevia o texto do `.cue`, que continuava referenciando o nome
  ORIGINAL (ex.: `FILE "Tekken 3 (USA) (Track 1).bin"`). O core procurava
  um arquivo que não existia com aquele nome e travava carregando pra
  sempre, sem nenhum erro visível -- só o emulador com o gif de loading
  parado. Corrigido: o admin-server agora reescreve as referências do
  `.cue` pros mesmos nomes sanitizados dos `.bin` antes de mandar pro
  container (`rewriteCueReferences` em `admin-server/server.js`).
- **Arcade/Neo Geo** (`fbneo`, pasta `mame`): o núcleo exige o romset em
  `.zip`, sempre com os arquivos **soltos na raiz do zip** (sem subpasta
  interna -- descoberto na prática: um romset com os arquivos dentro de
  `king/nome.rom`, por exemplo, falha). Os nomes/CRCs dos arquivos também
  precisam bater **exatamente** com a versão do FBNeo empacotada no core
  (ex.: `265-c1.c1` com CRC certo pro KOF2002) -- romsets de outra
  revisão do MAME, mesmo sendo o mesmo jogo, têm nomes diferentes e são
  rejeitados com uma lista clara do que falta. Isso é uma característica
  do FBNeo/MAME, não um bug daqui.
  **Sem BIOS separada**: os arquivos "comuns" que normalmente ficam numa
  `neogeo.zip` (`sm1.sm1`, `sfix.sfix`, `000-lo.lo`) precisam estar
  **dentro do zip de cada jogo** (romset "non-merged") -- o admin-server
  não separa BIOS de jogo.
  **Zipagem automática**: pra evitar o problema de subpasta acima, o
  admin-server monta o `.zip` ele mesmo (em memória, via `jszip`, nunca
  toca disco) a partir dos arquivos soltos enviados -- o organizador não
  precisa zipar nada, só selecionar todos os arquivos (jogo + comuns) de
  uma vez. O zip final é sempre plano.
  **Bug real corrigido em 2026-08-19 -- "Romset is unknown"**: o zip era
  nomeado com o `matchId` (rótulo livre e opcional de sessão, ex.: o
  organizador digitou "97" achando que era só um número de partida) em
  vez do nome real do romset esperado pelo FBNeo (ex.: `kof97.zip`). O
  core rejeitava com "Romset is unknown" por não reconhecer o nome do
  arquivo, mesmo com o conteúdo potencialmente correto. Corrigido: agora
  existe um campo dedicado `romName` (obrigatório só quando o console é
  Arcade/Neo Geo, validado em `arena.schema.ts`) -- é ele, não o
  `matchId`, que nomeia o `.zip` final. **Lembrete pra próxima partida
  Arcade**: `romName` precisa ser o nome exato do driver do FBNeo (ex.:
  `kof97`), e o KOF97 real ainda precisa de `m1` (som Z80) e `v1`+ (ADPCM)
  além dos `c1-c4`/`p1`/`s1` -- confira a lista completa do romset antes
  de tentar de novo.
- **DOS** (`dosbox_pure`, pasta `dos`): geralmente um `.zip` só já basta
  (esse continua sendo enviado pronto, sem zipagem automática).
- **Dreamcast** (`flycast`, pasta `dc`): aceita `.chd` sozinho (recomendado),
  ou `.gdi` + `.bin`/`.raw`, ou `.cdi`. A BIOS (`dc_boot.bin` e
  `dc_flash.bin`) precisa ir **junto no upload** -- o admin-server detecta
  esses nomes e coloca em `libretro/system/dc/` (onde o Flycast procura),
  enquanto a ROM fica em `assets/games/dc/`. Sem BIOS real o Flycast tenta
  HLE, mas jogos costumam falhar ou travar -- sempre envie os dois arquivos
  de BIOS junto com o jogo. MD5 esperados: `dc_boot.bin` =
  `e10c53c2f8b90bab96ead2d368858623`, `dc_flash.bin` =
  `0a93f7940c455905bea6e392dfde92a4`.

O endpoint `/create-match` do `admin-server` aceita múltiplos arquivos
(`multipart` campo `roms`, não mais singular, até 64) e um campo opcional
`platformFolder` (`psx`/`mame`/`dos`/`dc`) pra saber em qual subpasta
colocá-los.
**Importante:** a subpasta é criada e TODOS os arquivos são copiados pra
dentro dela **antes** de liberar o gate `/tmp/.rom-ready` -- o scan inicial
do worker (síncrono, no boot) é o único jeito confiável de o watcher
não-recursivo do CloudRetro reconhecer o conteúdo de uma subpasta (ver
seção "Fase 5" acima).

**Bug real corrigido em 2026-08-19 -- "Internal Server Error" / "Unexpected
field" ao enviar um SFIII (CPS-3)**: o limite de arquivos do campo `roms`
(multer, `upload.array("roms", N)`) era 32 -- generoso pra Neo Geo (KOF2002
tem uns 15), mas romsets CPS-3 (Street Fighter III e afins) costumam vir com
as SIMMs divididas em muitos chips pequenos e passam fácil disso. Quando o
limite estoura, o multer não devolve um erro claro de "arquivos demais" --
lança `LIMIT_UNEXPECTED_FILE` com mensagem genérica "Unexpected field", que
sem tratamento especial vira um 500 "Internal Server Error" puro e simples
pro organizador, sem pista nenhuma da causa real. Subimos o limite pra 64
**nos dois multers** (gamo-api em `arena.routes.ts` E o `admin-server` -- o
arquivo passa pelos dois em sequência, o segundo limite existe
independentemente do primeiro).

### Por que a BIOS não fica pré-carregada no sistema

Cogitamos deixar a BIOS de cada plataforma (Neo Geo, PS1 etc.) já
embutida na imagem/provisionamento, pra o organizador nunca precisar
enviar. **Decisão: não fazer isso** -- firmware/BIOS de console é
software protegido por direito autoral igual a um jogo (SNK, Sony etc.
são os donos), sem nenhuma exceção legal maior que a de uma ROM de jogo.
Manter uma cópia sempre disponível no sistema pra qualquer partida, de
qualquer usuário, é uma postura de risco diferente (e maior) do que o
upload pontual por partida que já temos: deixa de ser "o organizador
manda um arquivo efêmero pra UMA partida" e passa a ser "a plataforma
guarda e serve firmware protegido pra quem precisar" -- exatamente o tipo
de exposição que a arquitetura "ROM nunca em disco" foi desenhada pra
evitar desde o início deste projeto. A BIOS continua entrando pelo mesmo
upload por partida que a ROM do jogo (ver "Sem BIOS separada" acima).

## Versão do núcleo FBNeo fixada (2026-08-19)

Como a VM é destruída e recriada a cada "Desligar"/"Ligar" (mesmo motivo
do certificado do Caddy, ver seção Fase 3), o CloudRetro baixava a
**versão mais recente disponível** do núcleo FBNeo (Arcade/Neo Geo) do
buildbot em todo boot -- o que podia mudar silenciosamente quais
nomes/CRCs de romset um jogo espera de uma sessão de teste pra outra
(o CloudRetro só baixa um núcleo se o arquivo ainda não existir em
`assets/cores`, nunca verifica/atualiza por versão -- ver
`pkg/worker/caged/libretro/manager` no CloudRetro).

Corrigido com o mesmo mecanismo do certificado (`arenaServer.service.ts`):
`pinFbneoCoreIfMissing` guarda no Postgres, ao "Desligar", o
`fbneo_libretro.so` que estava em uso naquela sessão -- mas só na
**primeira vez** que existir um pra guardar (nunca sobrescreve depois,
diferente do certificado, que precisa renovar). `restorePinnedFbneoCore`
escreve esse arquivo de volta em `/opt/arena/assets/cores/` a cada
"Ligar", **antes** do `docker compose up` -- o worker encontra o núcleo
já lá e nunca baixa outro. Os demais núcleos (SNES, N64, PS1 etc.)
continuam se atualizando normalmente a cada sessão, sem nenhuma mudança.

**Importante**: isso fixa a *versão do núcleo*, não resolve por si só um
romset que já esteja com nome/CRC incompatível (ver seção acima) -- só
garante que, uma vez que algo funcione, continue funcionando nas próximas
sessões sem mudar por baixo. Como a arena não chegou a ficar de pé com
sucesso numa sessão desde que isso foi implementado, a primeira captura
ainda não aconteceu -- vai acontecer sozinha no próximo "Desligar" depois
de uma sessão em que o Arcade/Neo Geo tiver sido usado pelo menos uma vez.

## Segundo jogador só ouve o som, vídeo nunca aparece (bug real, 2026-08-19)

Reproduzido com SNES e depois com N64 (Killer Instinct Gold): quem inicia a
partida (organizador/admin) sempre funciona; um segundo jogador que entra
depois, no mesmo link de partida, carrega o som mas o vídeo nunca aparece,
mesmo esperando bastante.

**Causa**: o CloudRetro usa `"___"` (três underscores) como separador entre
o hash da sala e o nome do jogo no `roomId` (`pkg/games/launcher.go`), e o
código que lê esse `roomId` de volta (`ExtractGame`) usa `strings.Split`
sem limite -- se o nome do jogo já sanitizado contiver `"___"` em algum
lugar, ele é cortado ali, e o pedido do segundo jogador busca um nome de
jogo truncado que não existe (`couldn't find game info for the game ...`
nos logs do worker, com `CLOUD_GAME_WORKER_DEBUG=true`). Isso acontecia
porque nosso próprio sanitizador de nome trocava CADA caractere especial
por um `_` individual -- um nome como `Killer Instinct Gold (USA) (Rev
A).n64`, que tem duas tags entre parênteses coladas (`) (`), sanitizava pra
`..._Gold__USA___Rev_A_...`, gerando um `"___"` por coincidência bem no
meio do nome e colidindo com o separador do CloudRetro.

**Corrigido**: `sanitizeName()` em `admin-server/server.js` agora junta
QUALQUER sequência de caracteres especiais consecutivos num único `_` (em
vez de um `_` por caractere), então nunca produz `"__"` nem `"___"`. Não
precisou tocar em nada do CloudRetro -- o ajuste é só em como a gente
nomeia os arquivos antes de mandar pro tmpfs.

## Identidade visual do cliente web + links de partida (2026-08-20)

**Marca Gamo no cliente web**: o CloudRetro não tem sistema de tema (cores
e sprites de botão são valores fixos em `main.css`/`ui.css`, sem CSS
variables) -- em vez de reescrever esses dois arquivos por inteiro e
arriscar desalinhar do upstream, a marca entra por dois arquivos NOVOS,
puramente aditivos: `web/css/gamo.css` (brilho laranja em volta do
`#gamebody`, via `box-shadow` -- não é cortado pelo `overflow:hidden` do
próprio elemento, diferente de um filho posicionado fora da caixa) e uma
pequena injeção de logo dentro de `app.js` (elemento `fixed` separado do
`#gamebody`, `pointer-events:none`). `web/index.html` precisou de uma
cópia própria (original + 1 `<link>` novo) só pra carregar o CSS extra.

**Bug real descoberto ao vivo**: a primeira versão desse `index.html`
tinha um comentário HTML explicando os blocos condicionais do próprio
CloudRetro e citava a sintaxe deles literalmente. O `html/template` do Go
opera em texto puro -- não sabe o que é um comentário HTML -- então tentou
interpretar aquele texto como uma ação de template de verdade, desbalanceou
o par `if`/`end` e o *coordinator* **crashava** na inicialização
("panic: template: index.html:155: unexpected EOF", confirmado via
`docker logs`). Corrigido descrevendo a regra sem escrever os delimitadores
`{{ }}` literalmente dentro do comentário.

**Links de partida — reemissão e validade maior**: os links (organizador +
jogadores) só apareciam uma vez, no momento da criação -- sem forma de
recuperar se a página fosse atualizada antes de copiar (aconteceu na
prática). Agora `GET /api/arena/matches/:arenaMatchId/links` (gamo-api)
reemite tokens novos pra mesma partida sem tocar na VPS; no admin, botão
"Ver links" ao lado de "Finalizar". Validade do token subiu de 1h pra 5h
(decisão consciente pra campeonato -- ver comentário em `arena.service.ts`
sobre o trade-off real: um link vazado fica "válido" por mais tempo, mas o
dano concreto é alguém jogar no lugar do participante real, não uma falha
de dados -- a vitória continua registrada pro `userId` certo).

## N64 de cabeça para baixo + mais identidade visual (2026-08-20)

**Bug do N64 invertido -- diagnóstico ERRADO nesta seção, ver a seção
"N64 de cabeça para baixo -- causa real" mais abaixo pro fix de verdade.**
`Flipped()` no worker Go (`pkg/worker/caged/libretro/frontend.go`) retorna
`f.nano.IsGL()`, e o N64 (`mupen64plus_next`) é o único core deste deploy
com `isGlAllowed: true`. A hipótese inicial foi: o worker manda
`flip:true` incorretamente (framebuffer já sai certo nesse pipeline
Xvfb+llvmpipe) e bastava ignorar esse valor no cliente
(`gamoStripFlip`, removida depois). **Provado errado por teste real**: ao
forçar `flip:false`, TODOS os jogadores (staff, player 1 e 2) passaram a
ver a tela invertida -- antes só o player 2 tinha esse problema. Ou seja,
`flip:true` era necessário e correto; a causa de "só o player 2" era
outra (ver seção seguinte). Patch revertido.

**Catálogo do que mais dá pra customizar no cliente web** (perguntado
depois de ver que só a borda laranja tinha aparecido):
- Atribuição "Cloudretro (ɔ) 2026" (div `.source`, `main.css`): puramente
  cosmética, escondida via `display:none` em `gamo.css` -- risco zero.
- Fundo de página (`body`, antes um tile pequeno repetido): trocado pela
  arte da Gamo (`web/img/gamo-bg.jpg`, 2048x2048) via `background-size:
  cover` -- mecanismo simples, só precisa da imagem certa.
- Fundo do próprio `#gamebody` (`ui/bg.jpg`, estica 100%x100% num
  retângulo ~640x286): trocável do mesmo jeito, mas só vale a pena com uma
  imagem já cortada nessa proporção -- senão distorce.
- Skin completo do gamepad: são **18 sprites PNG individuais**
  (`web/img/ui/bt *.png`, `bong.png`, `FrameTEXT.png` etc.), cada botão
  posicionado via CSS absoluto. Reskinar de verdade = 18 artes novas do
  mesmo tamanho em pixel -- projeto de arte, não só CSS.
- Layout alternativo de controle / outro esquema de input: **não existe**
  nativamente (conferido em `settings.js` -- só tem remapeamento de
  teclado, espelhamento de vídeo, volume, forçar fullscreen, log level).
  Construir isso seria uma feature nova, não uma customização.

**Cache do navegador escondeu o logo por 2 dias**: o `app.js` mudou de
conteúdo mas continuava servido na mesma URL de sempre (`?v=3`, versão do
próprio CloudRetro) com `Cache-Control: max-age=259200`. Quem já tinha
aberto a Arena antes do deploy ficou com a cópia antiga em cache, sem
re-buscar do servidor -- por isso a borda apareceu (CSS era arquivo novo,
sem cache prévio) mas o logo não (mesma URL de sempre). Convenção adotada:
sempre que o CONTEÚDO de `app.js` mudar, bump o sufixo próprio
`?v=gamoN` (não o `?v=3` dos outros scripts, que é do CloudRetro).

## N64 de cabeça para baixo -- causa real (2026-08-21)

Depois de reverter o `gamoStripFlip` (seção acima -- provado errado),
voltou o relato original: só player 1 e 2 invertidos, staff/admin certo.
Achada a causa de verdade com um log temporário de diagnóstico
(`console.log` nos dois pontos onde `app.js` publica `APP_VIDEO_CHANGED`
+ um terceiro na resposta do `/verify`), testado em produção com os 3
papéis:

- **Staff** recebe `APP_VIDEO_CHANGE` com `flip:true` (correto) -- vem de
  um broadcast do coordinator (`pkg/worker/coordinatorhandlers.go`,
  dentro do bloco que só roda **na criação da sala**, via
  `app.VideoChangeCb(...)` + `r.Send(data)`). Esse broadcast só alcança
  quem **já estava conectado naquele exato momento** -- e como o staff é
  sempre quem cria a sala antes de qualquer jogador entrar, só ele recebe.
- **Player 1 e 2** (que entram DEPOIS que a sala já existe) nunca recebem
  esse broadcast (chegaram tarde demais) -- confirmado no log:
  `GAME_START av=null role=player`, e nenhum `APP_VIDEO_CHANGE` depois
  disso. O valor de `flip` no cliente fica parado no default (`false`)
  pra sempre, daí a tela invertida.

**Fix**: `auth-server/server.js` ganhou um segundo mapa `avByMatch`
(matchId -> `{w,h,a,s,flip,rot}`), do mesmo jeito que já existia
`roomByMatch` pro roomId. Em `app.js`, o staff reencaminha o av assim que
recebe (`arenaReportAv`, um `sub(APP_VIDEO_CHANGED, ...)` novo) pro
`POST /report-room` (mesma rota do roomId, `av` agora é um campo opcional
separado); o jogador aplica o `data.av` vindo do próprio `/verify` (que
agora também devolve `av`) antes de `startApp()`, em vez de depender do
timing do broadcast do CloudRetro. Testado ao vivo com staff + player 1 +
player 2 numa partida nova -- os 3 corretos.

Race teórica não testada: se um jogador entrar bem rápido, antes do
staff sequer ter recebido/reencaminhado o av (a criação da sala e o
primeiro frame do core são quase simultâneos, mas não instantâneos), o
`/verify` dele pode vir com `av: null` mesmo assim -- e como o loop de
poll do jogador para assim que `roomId` aparece (não continua esperando
o av), ele ficaria sem correção igual antes. Não apareceu nos testes,
mas se voltar a acontecer, é por aí.

## Logo dark mode + L/R visíveis + mapa de controle físico completo (2026-08-20)

**Logo**: trocado de `logo-gamo-light.svg` pra `logo-gamo-dark.svg` no
`app.js` (pedido depois de ver ao vivo -- a variante anterior não
destacava bem sobre o fundo escuro da Arena).

**Botões L/R visíveis na tela**: CloudRetro não desenha eles no gamepad
touch/mouse (só existem como tecla/botão de controle físico -- ver
`keys.js`/`joystick.js`). Adicionados dois `<div class="btn" data-key="l">`
/`data-key="r"` em `index.html` + estilo próprio em `gamo.css`
(`.gamo-shoulder-btn`) -- funcionam de graça porque QUALQUER elemento com
`data-key` já é reconhecido pelo sistema de input genérico
(`web/js/input/touch.js`), sem precisar de JS novo. Posição inicial (topo,
flanqueando a tela do jogo) é um primeiro palpite -- ajustar depois de ver
ao vivo.

**Bug real: mapa de controle físico padrão não tinha X, Y, L, R, L2, R2,
L3, R3**. `web/js/input/joystick.js` (não fazia parte dos overrides até
agora, adicionado). O mapa "KeyMap2" (usado por Windows/Mac/Linux fora dos
casos especiais de Firefox/Safari) só ligava A, B, Start, Select, Load,
Save, Help, Quit e o D-pad digital -- pra um controle padrão tipo Xbox
plugado via USB/Bluetooth, os botões de ombro/gatilho/clique do analógico
literalmente não tinham pra onde ir. Corrigido seguindo o "standard
gamepad" do W3C (índices 0-15 = os 16 botões do RetroPad por completo);
Load/Save/Help/Quit saíram do controle físico nesse processo (continuam
no teclado e no clique da tela -- e nem deveriam ser acionáveis por engano
durante uma partida de torneio). Só o branch padrão (else) foi tocado --
os casos especiais de Android/Firefox/Safari/PS3 continuam como estavam,
sem confirmação de que têm o mesmo problema.

**Analógico**: já funcionava antes de qualquer mudança -- o toggle
"dpad-toggle" (chave ao lado do campo "room id...") alterna entre o
analógico emular D-pad digital (padrão) e mandar os eixos crus pro jogo
(`AXIS_CHANGED` -> `retropad.setAxisChanged`). Não precisou de código
novo, só vale saber que esse toggle existe.

**Encadeamento de cache-bust pelo importmap**: `input.js` é carregado via
o importmap (`"input": "./js/input/input.js?v=3"`), e ele mesmo importa
`joystick.js?v=3` -- os dois com a versão compartilhada do CloudRetro. Pra
sobrescrever qualquer um dos dois sem cair no mesmo problema de cache do
logo, teve que bumpar a entrada do importmap (`?v=gamo1`) E o import
interno de `joystick.js` dentro do `input.js` sobrescrito (`?v=gamo1`) --
regra registrada no comentário do topo do `index.html`.

## Tema preto+laranja, silhueta, e UI simplificada pro jogador (2026-08-20)

**Tema preto+laranja completo**: além do brilho em volta de `#gamebody`,
agora tem um degradê laranja por cima da textura original
(`background-blend-mode`) e os botões A/B/X/Y recoloridos via
`filter: sepia() saturate() hue-rotate()` -- técnica que tinge um sprite
cinza monocromático pra qualquer matiz sem precisar de PNG novo (não dá
pra pintar imagem com `color` do CSS, mas filter consegue). Resultado
visual confirmado ao vivo pelo usuário -- ficou razoavelmente parecido com
a referência de "controle ideal" que ele mandou, considerando que é tudo
CSS, sem arte nova.

**Silhueta de controle (tentativa, mantida mas sem mais investimento)**:
`#gamo-shell`, elemento separado (não filho de `#gamebody`, que tem
`overflow:hidden` e cortaria qualquer coisa fora da própria caixa) atrás
do gamepad, com um `clip-path: polygon(...)` tentando um contorno mais
"grip" (pontas largas, meio estreito). Testado ao vivo -- efeito pouco
perceptível pra justificar mais tempo nisso; usuário pediu pra não
investir mais aqui por ora. Código fica como está (não reverter), só não
iterar mais.

**UI simplificada por papel (staff vê tudo, jogador só vê ação de jogo)**:
a pedido explícito -- pro jogador comum (`role !== "staff"`), escondido:
botão "W" (debug de worker), "?" (help), campo "room id...", toggle do
D-pad, SHARE, QUIT, LOAD, SAVE e o texto de atalhos de teclado embaixo da
tela (`#guide-txt`). O único não-gameplay que sobra é "Controles" (era
"OPTIONS" -- ver próximo item). Mesmo padrão que já existia pra esconder o
seletor de jogador do jogador comum, só estendido pra mais elementos, no
mesmo bloco de `app.js` (`data.role !== "staff"`). Sempre via
`el.style.display = "none"` (inline) -- não a classe `.hidden`, porque
LOAD/SAVE são reexibidos via `gui.show()` (`classList.remove('hidden')`)
quando o jogo começa, e inline vence a classe na especificidade do CSS
independente da ordem.

**"OPTIONS" -> "Controles"**: o label original vem desenhado dentro do
próprio PNG (`bt OPTIONS.png`), não tem texto real pra editar. Troca:
remove o `background-image`, `#btn-settings` ganha texto real "Controles"
+ estilo próprio (`.gamo-flat-btn`, cinza chumbo com bisel, igual
SELECT/START) em vez do sprite.

**Pendências abertas (feedback do usuário, não implementadas ainda)**: o
visual do L/R ("ainda feio") fica pra melhorar depois.

## Sobre a ROM de teste

Use uma ROM de um jogo que você **possui legalmente** (cartucho físico que
você tem, dump feito por você) só pra este teste técnico. Ela vai ser
copiada manualmente pro diretório `tmpfs` do container durante o teste e
some quando o container parar ou a instância for destruída — não fica
salva em nenhum lugar deste repositório nem em disco do servidor.

## Checklist de encerramento do teste do dia

- [ ] Parar os containers (`docker compose down`)
- [ ] Confirmar que a pasta tmpfs de ROMs não existe mais fora do container
- [ ] **Destruir** a instância na Vultr (não só desligar)
- [ ] Anotar aqui (ou me contar) o que funcionou/não funcionou, pra
      atualizar o plano antes do próximo teste

## Desligamento automático por inatividade (2026-09-01)

"Ligar"/"Desligar" era 100% manual — já aconteceu de esquecer ligada depois
que o evento acaba, cobrando à toa na Vultr (cobra por hora enquanto a
instância existir, mesmo desligada — só destruindo pra parar de verdade).

O CloudRetro não expõe nenhum sinal de ocupação pronto pra uso: checado
direto no código-fonte upstream (`pkg/coordinator/hub.go`, `user.go`,
`monitoring.go`, `pkg/worker/room/room.go`) — sem contador de
sessões/salas, sem endpoint REST, e as métricas Prometheus embutidas ficam
desligadas por padrão e mesmo ligadas não têm gauge de ocupação. Só existe
`Hub.GetServerList()` (status "busy" do worker, sem granularidade de
usuário) e nada de idle-timeout nativo.

O sinal usado, em vez disso: `pkg/coordinator/user.go` mostra que a conexão
WebSocket do navegador com o *coordinator* (porta 8000) fica aberta durante
toda a sessão — `User.Disconnect()` só roda em desconexão de verdade, não
logo após o handshake/início da partida. Então **contar conexões TCP
ESTABLISHED na porta 8000, dentro da network namespace do próprio processo
do coordinator** (lido do host via SSH, `cat /proc/<pid>/net/tcp` — não
`docker exec`, pra não depender de `ss`/`netstat` estarem instalados na
imagem) é o jeito mais direto de saber "tem alguém na Arena agora", sem
fork/patch no CloudRetro e sem expor porta nova. Implementado em
`gamo-api/src/modules/arena/arenaServer.service.ts`
(`getArenaActiveConnections`/`countEstablishedOnPort`) e
`gamo-api/src/jobs/arena-inactivity.ts` (checa a cada 5 min; 2h sem nenhuma
conexão → destrói a VM sozinha, com e-mail de aviso ~15 min antes).

Decisão consciente: o relógio de 2h conta a partir do **boot** da VM, não só
depois do primeiro uso — se ligar a Arena de manhã pra um evento à noite e
ninguém entrar por 2h, ela desliga sozinha antes do evento começar. Trade-off
aceito em troca de simplicidade (sem isso, precisaria de um sinal extra pra
saber "está esperando o evento começar" vs. "esqueceram ligada").

## Título da aba/preview mostrava "Cloud Retro" em vez de "Arena Gamo" (2026-09-22)

O `web/index.html` original do CloudRetro (`overrides/web/index.html`) vinha
com `<title>Cloud Retro</title>`, `og:site_name` e o rótulo do rodapé do
player (`.screen__footer`, aparece ao passar o mouse sobre a tela do jogo)
todos com o nome do projeto open source, não da Gamo — visível na aba do
navegador e em preview de link (WhatsApp/Twitter/Discord). Trocado pra
"Arena Gamo" nesses 3 pontos (título, `og:site_name`/`og:title`/
`og:description`, rótulo do rodapé do player).

Deixado como estava, de propósito: os comentários de código nos arquivos de
override (`app.js`, `auth-server/server.js`, `admin-server/server.js`, este
README) continuam citando "CloudRetro" — ali é o nome técnico correto do
motor open source por baixo do capô (github.com/giongto35/cloud-game), trocar
pra "Arena Gamo" nesses comentários ficaria factualmente errado pra quem for
mexer no código depois. Também não mexi no `<div class="source">` do rodapé
("Cloudretro (ɔ) 2026" + link pro repositório) — já vem oculto via
`gamo.css` (`.source { display: none; }`), então nunca aparece pro jogador;
mantive o crédito ao projeto original presente (mas invisível) por ser uma
cortesia de atribuição open source, não uma escolha de branding visível.

**Cache**: o coordinator serve `index.html` com `Cache-Control` de até 3
dias (`coordinator.monitoring`/`server.cacheControl` no `config.yaml`, ver
seção de cache mais acima neste arquivo pro mesmo problema com `app.js`).
Quem visitou a Arena numa sessão anterior recente pode continuar vendo o
título antigo até o cache expirar ou dar um hard-refresh — não tem como
"bumpar versão" do documento principal como se faz com os `?v=` dos
scripts/CSS (é o HTML raiz, não um recurso versionado).

## "Ligar Arena" travado pra sempre depois de um redeploy no meio (2026-09-22)

Um admin clicou "Ligar Arena"; um redeploy do `gamo-api` (Railway) aconteceu
no meio do provisionamento e destruiu o processo Node que estava tocando a
criação da VM. A VM na Vultr ficou órfã (cobrando, mas ninguém terminando de
configurá-la) e o painel travou de vez: `provisionState` (o "em que fase
está o Ligar Arena") só existia em memória, então o processo novo nasceu
achando que estava tudo "idle" — mas como a VM existia e não respondia
saudável, `getArenaServerStatus()` caía no fallback e reportava
`provisioning: true` pra sempre. Isso desabilitava os dois botões ao mesmo
tempo (`disabled={... || status.provisioning}`) — sem nenhuma saída possível
pela própria tela. Só descobri investigando logs do Railway e chamando a API
na mão. Ver também: nenhum comando SSH (`sshExec`) tinha timeout, então uma
trava de verdade na VM (não só a do redeploy) travava
`runProvisioning()` do mesmo jeito, mesmo com o processo vivo e saudável.

Corrigido em 3 frentes:
1. `sshExec` ganhou timeout (8min) — um comando remoto travado agora rejeita
   em vez de prender o provisionamento pra sempre.
2. `ArenaActivityState` (Postgres) ganhou `provisioningStartedAt` — grava
   quando "Ligar Arena" começa, sobrevive a um redeploy. Um watchdog
   (`gamo-api/src/jobs/arena-inactivity.ts` ->
   `runArenaProvisioningWatchdogJob`, mesmo `setInterval` de 5min do
   desligamento por inatividade) força a parada sozinho depois de 15min
   travado — só para e avisa por e-mail, não tenta ligar de novo sozinho
   (decisão consciente: evita gastar em loop se a causa for sistêmica).
3. `gamo-admin/src/pages/arena/create.tsx`: removida a trava global dos
   botões — agora sempre tem uma ação disponível (`Ligar Arena` /
   `Desligar Arena` / `Forçar parada`, este último visível e clicável
   mesmo com `provisioning: true`, o botão de emergência). Também ganhou
   contadores "Ligada há..."/"Provisionando há..." (poll de 30s enquanto
   rodando, 4s enquanto provisionando).

## Worker crasha (panic) com 2 jogadores em certos jogos de Arcade (2026-09-22)

Reportado com Darkstalkers 3 e Marvel vs Capcom (ambos Arcade/FBNeo): o
staff entra normal, mas alguns segundos depois do 2º jogador (link
distribuído) entrar, o jogo trava pra todo mundo -- atualizar a página dá
erro. Tekken 3 (PS1, core `pcsx_rearmed`) não reproduz.

Causa raiz confirmada nos logs do container `cloud-game` na VM (via SSH,
`docker compose logs cloud-game`): **panic real no worker do CloudRetro**,
não uma trava de rede:

```
panic: runtime error: index out of range [0] with length 0
goroutine ... pkg/worker/media.(*GstMediaPipe).pushAudio.func1(...)
	pkg/worker/media/gstreamer.go:333
```

`pushAudio()` faz `C.pushAudioBuf(..., unsafe.Pointer(&data[0]), ...)` sem
checar se `data` (um `[]byte` vindo de `g.audioCh`) está vazio -- quando o
core do libretro (FBNeo, nesse caso) emite um buffer de áudio de tamanho 0
(acontece com mais frequência quando o pipeline de áudio é reconstruído pra
um 2º peer entrando), o worker sofre panic e o processo inteiro morre. O
`arena-admin` (container separado, health check do gamo-api) continua de
pé, então **isso não aparece como Arena fora do ar** pro sistema de status
-- só quebra o jogo em si. Bug real da biblioteca upstream
(github.com/giongto35/cloud-game), não do código nosso.

Corrigido com um patch aplicado no `runProvisioning()`
(`gamo-api/src/modules/arena/arenaServer.service.ts`), logo depois do
`git clone` do CloudRetro e antes do `docker compose up --build`: um
`sed` adiciona `|| len(data) == 0` no mesmo guard que já existe ali
(`if g.reinit.Load() || g.a == nil { ... }`) -- mesmo padrão defensivo, só
cobrindo o caso que faltava. Um `grep -q` roda antes (falha alto e claro se
a linha não existir) e depois (confirma que o patch pegou) -- como
clonamos sempre `--depth 1` do `master` (sem fork nosso), se o upstream
mudar essa função num clone futuro o patch para de bater silenciosamente
sem isso; com o `grep -q`, o provisionamento inteiro falha de forma visível
em vez de silenciosamente voltar a ficar vulnerável.

**Só entra em vigor na próxima VM recriada** (o patch roda durante o
`git clone`/build, não em uma VM já rodando) -- uma VM já ligada continua
vulnerável até ser desligada e ligada de novo.

## Dreamcast não carrega / worker morre ao iniciar jogo (2026-09-22)

Reportado com Street Fighter III 3rd Strike (Dreamcast, `.chd` + BIOS):
a partida era criada com sucesso (`folder=dc`, arquivos no lugar certo),
WebRTC conectava, mas ao dar StartGame o worker crashava (`Exited (1)`) e
atualizar a página quebrava -- `cloud-game-local` ficava morto.

Causa raiz confirmada nos logs do container:

```
Libretro core load: assets/cores/flycast_libretro.so
error="couldn't load the lib: libgomp.so.1: cannot open shared object file: No such file or directory"
```

O core Flycast baixa certo do buildbot, mas a imagem worker do CloudRetro
não inclui `libgomp1` (GNU OpenMP). Corrigido com patch no `Dockerfile`
durante o provisionamento (`arenaServer.service.ts`): adiciona `libgomp1`
junto das deps de runtime (`libxext6`). **Precisa rebuild da imagem**
(`docker compose build cloud-game`) -- só recriar o container no
`create-match` não basta.

**Lembrete sobre BIOS**: `dc_flash.bin` precisa bater com o dump esperado
pelo Flycast (MD5 `0a93f794...`); um flash de região errada pode impedir
boot mesmo depois do fix do libgomp.

**Segundo bug (SIGSEGV ao iniciar jogo, 2026-09-22)**: depois do libgomp,
o core carregava mas o worker morria com `SIGSEGV` logo ao abrir o jogo.
Causa: Xvfb em `320x240x16` + Flycast com resolução interna `640x480` e
`threaded_rendering` ligado num pipeline OpenGL headless (llvmpipe).
Corrigido: Xvfb `640x480x24`, `flycast_threaded_rendering: disabled`,
`vfr: false` no config do Flycast. Precisa recriar containers (`xvfb` +
`cloud-game`) -- só `create-match` não aplica mudança de Xvfb/config.

**Terceiro bug (`X Error: BadMatch`, causa raiz de verdade, 2026-09-23)**:
mesmo com os dois fixes acima, o worker ainda travava (sem nenhum log do
Mesa/GL -- confirmado ligando `LIBGL_DEBUG=verbose`/`MESA_DEBUG=1` na VM ao
vivo) assim que o jogo começava a carregar:

```
X Error of failed request:  BadMatch (invalid parameter attributes)
  Major opcode of failed request:  0 ()
```

Causa raiz, achada lendo o código-fonte real do CloudRetro
(`pkg/worker/caged/libretro/graphics/rgfw.go`, função `RGFW_createWindow`):
a janela OpenGL compartilhada do worker é criada **uma única vez**, com o
visual **padrão da tela X** (`DefaultVisual`/`DefaultDepth`) -- que não
reserva stencil buffer. O Flycast exige um contexto OpenGL com stencil
buffer (confirmado no código-fonte dele, `shell/libretro/libretro.cpp`,
`params.stencil = true`). Quando o core tenta vincular esse contexto
(que precisa de stencil) na janela (cujo visual não tem stencil),
`glXMakeCurrent` falha com `BadMatch` **antes de qualquer chamada OpenGL de
verdade** -- por isso nenhum log do Mesa aparece, é um erro de negociação
pura do X11/GLX. N64 (`mupen64plus_next`, também `isGlAllowed: true`) nunca
bateu nisso porque não pede stencil buffer.

Corrigido com um patch (aplicado durante o provisionamento, junto dos
outros patches no CloudRetro recém-clonado, ver `arenaServer.service.ts` ->
`patchRgfwWindowVisual`) que reescreve `RGFW_createWindow` pra escolher o
visual da janela via GLX (`glXChooseFBConfig` + `glXGetVisualFromFBConfig`,
reservando stencil/depth/alpha de propósito) em vez do
`DefaultVisual`/`DefaultDepth` puro do Xlib -- diferente dos outros
patches (uma linha via `sed`), esse troca a função inteira, por isso o
código lê o arquivo de verdade via SSH e reescreve via SFTP (com um
`grep`/`includes` de segurança: se o upstream mudar essa função num clone
futuro, falha alto e claro em vez de aplicar silenciosamente nada).

**Isso também só entra em vigor na próxima VM recriada** -- mesma
observação dos patches anteriores.

**Pegadinha real do próprio patch acima (build quebrado, 2026-09-23)**: a
primeira versão desse patch quebrou o build inteiro do `cloud-game`
(`too many errors`, `invalid character '?'` -- erros de sintaxe **Go**,
não C, num arquivo C). Causa: `rgfw.go` inteiro vive dentro de **um único**
comentário de bloco (`/* ... */`) do preâmbulo cgo, do topo do arquivo até
`import "C"`. O comentário explicativo que o patch adicionava usava
`/* ... */` -- e como comentário de bloco em C não aninha, o `*/` dele
fechava o comentário de fora cedo demais, fazendo o resto do arquivo (tudo
depois daquele ponto) ser lido como **código Go de verdade** em vez de C,
gerando aquela cascata de erros bizarros. Pior: a correção **v1** trocou
para comentário `//`, mas o TEXTO do comentário ainda **citava** os
caracteres `/* */` como exemplo (explicando a regra) -- e isso sozinho já
basta pra disparar o mesmo bug, já que o parser não distingue "comentário
`//` que menciona `*/`" de um `*/` de verdade. Corrigido de vez descrevendo
a regra sem nunca digitar os caracteres literais. Regra geral pra qualquer
patch futuro nesse arquivo (ou em qualquer `.go` com preâmbulo cgo grande):
**nunca escrever `/*` ou `*/` dentro de um comentário novo aqui, nem como
exemplo** -- só `//`, e nunca citando os delimitadores de bloco.

## Investigação de travamento/lentidão reportado por usuários (2026-09-28)

Vários relatos de tela preta, travamento e lentidão durante partidas reais
(confirmado com log de uma sessão ao vivo de SNES, `umk3.sfc`, com 3
pessoas -- staff + 2 jogadores). Investigação feita com a Arena ligada em
produção, sem ninguém mais usando.

**Causa raiz confirmada: timeout de ping/pong do WebSocket agressivo
demais.** `pkg/network/websocket/websocket.go` (upstream do CloudRetro)
define:

```go
pingTime       = pongTime * 9 / 10
pongTime       = 7 * time.Second
```

Essa é a MESMA conexão usada durante a partida inteira pra sinalização
(coordinator ↔ jogador **e** coordinator ↔ worker) -- o vídeo/áudio em si
vai por WebRTC/UDP direto, fora dela. Só 7s de tolerância é pouco: qualquer
soluço breve -- rede do jogador, ou o próprio processo do worker sem CPU
por um instante (ele roda o núcleo do emulador **e** a codificação de
vídeo no mesmo processo) -- faz o coordinator achar que a ponta morreu e
fecha a sala inteira. Todo mundo desconecta junto, mesmo o worker
continuando vivo. O log real batia exatamente com isso: desconexões
repetidas a cada 10-40s, alternando `"read tcp ...: i/o timeout"` e
`"websocket: close 1001 (going away)"`, com `TerminateSession` derrubando
a sala toda vez.

Corrigido (patch em `arenaServer.service.ts` -> `runProvisioning`, mesmo
padrão `sed` de uma linha já usado nos outros patches): `pongTime` de 7s
pra 45s. **Validado ao vivo**: criei uma partida real (mesma ROM do
incidente, SNES), abri staff+P1+P2 num navegador de verdade (Playwright,
headless) e deixei rodando 3 minutos -- zero desconexões, contra os 4+
cortes que o log original mostrava nesse intervalo. CPU dos containers
ficou em 22-28% (de 2 vCPUs) o tempo todo, estável -- **por enquanto não
achei evidência de que precise trocar/aumentar a máquina da Vultr** pra
esse cenário (3 pessoas, SNES). Vale reavaliar se voltar a acontecer com
jogos mais pesados (Arcade, N64) ou mais gente conectada.

### Corrida "worker ainda não terminou de subir" (mesma investigação)

O `worker` só começa a inicializar de verdade DEPOIS que `/tmp/.rom-ready`
existe (`docker-compose.yml`: `... while [ ! -f /tmp/.rom-ready ]; do sleep
0.2; done; ./worker`). O `admin-server` (`create-match`) tocava esse
arquivo e respondia "pronto" pro gamo-api **sem esperar** o worker de
verdade terminar de carregar o núcleo e se registrar no coordinator --
media ~1.3s pra um núcleo leve (SNES) nesse teste, mas cores mais pesados
(Arcade/FBNeo, N64, Dreamcast) devem demorar mais. Quem clicasse no link
rápido demais nessa janela caía em "No free slots" **mesmo sem mais
ninguém usando a Arena**.

Corrigido: `create-match` agora espera o log real de registro do worker
(`docker logs -f cloud-game-local`, procurando `"worker id:"`, que é a
linha que o coordinator loga assim que aceita a conexão do worker) antes
de responder -- em vez de confiar em tempo de upload da ROM por
coincidência. Timeout de 20s antes de desistir e devolver erro claro.

### Logs dos containers do jogo não sobreviviam ao desligar a Arena

Os logs do coordinator/worker (onde apareceu a pista do bug acima) só
existiam em memória enquanto a VM estava de pé -- qualquer desligamento
(manual, inatividade de 2h, ou o watchdog de provisionamento travado)
destruía a VM inteira e levava o histórico junto. Todo incidente já
investigado virava arqueologia às cegas. Corrigido: `stopArenaServer`
agora captura `docker logs cloud-game-local --tail 500` por SSH e loga via
`console.log` ANTES de destruir a instância -- cai no log do próprio
gamo-api, que o Railway já retém por deployment (sem precisar de infra
nova).

### Abrir o mesmo link 2x (o usuário perguntou se isso trava)

Testado ao vivo (Playwright, 2 abas com o mesmo link):

- **Link do staff/admin aberto 2x**: a 2ª aba recebe `GAME_ERROR_NO_FREE_SLOTS`
  (mensagem "No free slots" na tela) e não entra -- a 1ª aba continua
  funcionando normal. Não trava nada, só recusa a segunda tentativa (é o
  comportamento esperado: só quem cria a sala pode ser staff, e a sala já
  existe).
- **Link de um jogador (P1/P2) aberto 2x**: **não dá erro nenhum** -- as
  duas abas conectam na mesma sala/slot em paralelo, cada uma com seu
  próprio stream de vídeo/áudio. Isso significa 2x a carga de codificação
  pro mesmo slot, e as DUAS abas mandam input pro mesmo jogador (o core
  recebe comandos intercalados de ambas) -- na prática, controles
  "brigando" entre si. **Provável causa real caso alguém tenha reaberto o
  link de jogador sem fechar a aba antiga** (reload, ou duas pessoas
  usando o mesmo link acidentalmente). Não corrigido ainda -- exigiria
  mudar a lógica de sessão/sala do CloudRetro (derrubar a conexão antiga
  do mesmo slot quando uma nova aparece), que é uma mudança mais invasiva
  no código upstream. Registrado aqui como próximo passo em aberto, não
  como bug resolvido.

### O que NÃO foi mudado (fica pra decisão futura)

- **Plano da VM (2 vCPU / 4GB, `voc-c-2c-4gb-50s`)**: sem evidência de que
  precise upgrade no cenário testado -- não mexi nisso.
- **`patchRgfwWindowVisual`** (o patch de visual GLX da janela, adicionado
  durante a investigação de Dreamcast em 2026-09-23): sessões anteriores
  já levantaram suspeita de que esse patch pode ter sido a causa errada
  (ou até ter regredido o comportamento de outros núcleos 3D -- N64 é o
  único outro core com `isGlAllowed: true`) -- nunca foi totalmente
  resolvido nem revertido. Não mexi nisso nesta rodada (fora do escopo do
  que foi reportado, e testar exigiria uma ROM de N64 em mãos). Fica
  registrado pra retomar quando o Dreamcast/N64 voltar a ser prioridade.
- **Dedup de sessão por slot** (ver seção acima sobre link de jogador
  aberto 2x): não implementado.

## Mapeamento de controle físico não funcionava pra parte dos usuários (2026-09-29)

Relato: apertar botão do controle físico não fazia nada (ou acionava o
botão errado), só o teclado funcionava de verdade -- "na maioria das vezes
o controle já vem bem configurado" (comportamento correto pra maioria),
mas não pra todo mundo.

**Causa raiz**: `joystick.js` (nosso override, mapa de controle) aplica
uma tabela fixa de índices (0-15, padrão "standard gamepad" do W3C) pra
QUALQUER controle conectado, sem checar `gamepad.mapping`. Isso só é
válido quando o navegador reconhece o controle como `"standard"` --
controles Xbox/PlayStation/Switch Pro via Bluetooth/USB nos navegadores
principais quase sempre são. Mas boa parte do público da Gamo é
colecionador e usa **adaptador USB pra controle original** (SNES/NES/
Genesis etc.), que o navegador expõe como `mapping: ""` (não reconhecido)
-- índices de botão completamente diferentes por adaptador. O próprio
CloudRetro já documenta essa inconsistência (issue upstream
[#14](https://github.com/giongto35/cloud-game/issues/14), "controller map
is not same among platforms") mas nunca resolveu de verdade -- só tem
heurísticas por navegador/SO, nenhuma checagem do campo real que o
navegador expõe.

**Corrigido em duas partes, as duas só entram em ação quando
`gamepad.mapping !== "standard"` (zero mudança de comportamento pra quem
já funcionava):**

1. **Rede de segurança**: sem calibração salva, o controle fica inerte
   (nenhum botão físico faz nada) em vez de acionar o botão errado, e
   mostra um aviso ("Controle não reconhecido... Configure em
   Controles"). Antes disso, o comportamento era pior que nada fazer --
   acionava ação errada silenciosamente.
2. **Assistente de calibração manual** (tela Controles > "Meu controle"):
   pergunta um botão do RetroPad de cada vez ("aperte o botão
   correspondente a A..."), com Pular/Cancelar, trata tanto botão normal
   quanto D-pad-como-eixo (comum em adaptador antigo), mostra uma tela de
   teste ao vivo (aperta o botão físico, vê o gamepad na tela acender)
   antes de salvar. Fica salvo no navegador da própria pessoa
   (localStorage, chave = `gamepad.id`), nunca no nosso banco -- por
   dispositivo/adaptador, não por conta Gamo.

**Onde vive**: `overrides/web/js/input/joystick.js` (detecção +
lógica de captura/mapa customizado, função `activateGamepadMapping` +
API `joystick.calibration.*`) e `overrides/web/js/settings.js` (novo
override -- não existia antes; a tela "Controles" inteira do CloudRetro
upstream, com a seção "Meu controle" adicionada por cima, 100% aditivo --
nenhuma linha original removida/alterada, conferido por diff contra o
upstream). `gamo.css` ganhou o estilo do assistente.

**Validado sem precisar de controle físico não-padrão em mãos**: simulei
um gamepad via `navigator.getGamepads` sobrescrito no navegador
(Playwright), cobrindo -- controle "standard" continua funcionando
IDÊNTICO a antes; controle não-reconhecido fica inerte até calibrar;
assistente completo funciona ponta a ponta (pergunta certo, captura o
botão físico certo, mostra na revisão, acende ao vivo no teste); depois
de salvo, funciona igual jogo normal sem precisar recalibrar; reconectar
o MESMO controle recarrega a calibração salva sozinho; e o cenário que
mais preocupava -- fechar no "X" no MEIO do assistente, sem terminar --
não deixa nada configurado pela metade (continua oferecendo "Configurar",
não salva nada parcial). 12 checagens automatizadas, todas passando.

**O que não foi testado**: um controle físico não-padrão de verdade na
mão de alguém (só simulado). Se algum comportamento específico de um
adaptador real escapar da simulação (ex.: D-pad codificado como um único
eixo "hat" combinando 8 direções em vez de eixos X/Y separados), o
assistente pede cada direção do D-pad separadamente e deveria capturar
mesmo assim, mas vale confirmar na prática assim que possível.

## Painel "Controles" some atrás do jogo, só a borda muda (2026-09-29)

Relato (com print): clicar em "Controles" durante uma partida real não
mostrava o painel -- só a borda do emulador ficava reta em vez de
arredondada (efeito colateral conhecido do `gui.panel` do próprio
CloudRetro, que zera o border-radius do `#gamebody` enquanto qualquer
painel está aberto). Reproduzi ao vivo (partida real, `umk3.sfc`) logo
depois de terminar o assistente de calibração acima e o painel abriu
perfeitamente -- print incluído no diagnóstico -- então pedi pro usuário
dar um hard-refresh (achando que fosse cache do navegador). Não resolveu;
o usuário mandou 2 prints novos confirmando que continuava igual.

**Causa raiz**: `#settings` e `#screen` são irmãos (os dois filhos de
`#gamebody`, ver `index.html`). O CloudRetro upstream resolve a
sobreposição normal com `#screen { z-index: -1 }` (comentário original:
"popups under the screen fix"). Isso funciona para a UI comum -- mas
**não** quando `#screen` está em fullscreen nativo do navegador (opção
"Force fullscreen" ligada nas Opções, ou a tecla F apertada durante o
jogo): a Fullscreen API do navegador desenha o elemento fullscreenado numa
camada acima de **toda** a página (o "top layer" da spec), inclusive acima
de irmãos com z-index maior -- não é um bug nosso nem do CloudRetro, é
como a spec de Fullscreen funciona mesmo. O painel liga certinho no DOM (a
classe `hidden` sai, `display` vira `flex`, tamanho correto) só que, na
prática, o navegador pinta `#screen` por cima dele de qualquer jeito.
Reproduzi isolado (HTML/CSS mínimo, fora da Arena, com os mesmos z-index
reais do `gamo.css`/`ui.css`): com `#screen` fullscreenado,
`document.elementFromPoint()` no centro exato de `#settings` aponta pra
`#screen`, confirmando a causa -- e explica por que meu primeiro teste
"funcionou" (a sessão de teste nunca tinha entrado em fullscreen nativo,
só o usuário real tinha).

**Corrigido em** `overrides/web/js/settings.js` (arquivo que já é nosso
override) -- fix cirúrgico só ali, sem tocar em `screen.js`/`env.js`
upstream (que cuidam de cursor, footer e resize do stream durante
fullscreen, não queria arriscar mexer nisso à toa): ao abrir o painel de
Controles, se o navegador estiver em fullscreen sai automaticamente; ao
fechar o painel, volta pro fullscreen exatamente como estava antes (se não
estava, não mexe em nada). `index.html` bump `settings.js?v=gamo1` ->
`?v=gamo2`.

## Remapeamento de tecla do teclado "não salvava" (2026-09-29)

Descoberto pelo usuário logo depois do fix acima -- assim que deu pra ver o
painel de Controles de verdade, tentou remapear (ex.: botão "x" pra tecla
"1", ou WASD pro movimento) e "não marcava a tecla nova". Não é regressão
do fix do fullscreen (painel abre e funciona normalmente) nem bug novo --
é um comportamento upstream que sempre existiu, só nunca visível/testável
antes (o painel estava sempre escondido atrás do jogo pra quem usa
fullscreen).

**Causa raiz**: `onKeyChange` (upstream, `settings.js`) recusa o
remapeamento quando a tecla física escolhida **já está em uso por outra
ação** -- ex.: "Digit1" já vem mapeado de fábrica pra `pad1` (trocar de
jogador), então tentar mapear "x" pra "Digit1" é recusado. Isso em si é
razoável (não dá pra ter 2 ações na mesma tecla), só que a recusa era
**100% silenciosa** -- só um `console.warn` que ninguém vê -- a tela
voltava pra lista normal e parecia que simplesmente não tinha feito nada.
Boa parte das teclas que o usuário testou (W = join, A = l, S = r) já
estavam ocupadas por outras ações no mapa padrão, por isso a impressão de
"nada salva".

Reproduzido isolado (mesma técnica do bug do fullscreen -- clone do
upstream + overrides aplicados por cima, servido localmente, sem precisar
da VM): clicar no botão da ação "b" e apertar "Digit1" -- console mostra
`There are old settings for key: pad1, won't change!` e o binding
realmente não muda; testar com uma tecla livre (ex. "KeyG") funciona
normal.

Depois de reportar isso, o usuário testou mais e trouxe mais 2 problemas
no mesmo fluxo -- os três (silêncio no conflito, trava na 2ª troca
seguida, linha pula pro fim da lista) foram investigados e corrigidos
juntos, porque os 3 são sintoma da mesma área de código:

1. **Silencioso no conflito** (acima) -- usuário pediu explicitamente pra
   TROCAR em vez de só avisar: mapear "x" pra uma tecla que já é de outra
   ação deveria mover essa ação pra tecla antiga do "x", não recusar.
2. **2ª troca seguida não pega** -- "configuro uma tecla, tento configurar
   a próxima, aperto a tecla e não acontece nada -- preciso fechar e abrir
   o modal de novo". Tentei reproduzir isolado (clique + tecla livre,
   repetido várias vezes seguidas, com e sem conflito no meio) e SEMPRE
   funcionou -- não bate com um bug separado. Suspeita forte (não
   100% confirmada): é o mesmo bug 1 disfarçado -- a maioria das teclas
   "óbvias" pra testar (WASD, números) já está ocupada por outra ação no
   mapa padrão, então a "2ª tentativa" muito provavelmente também esbarrava
   no silêncio do bug 1, e reabrir o modal só coincidia com escolher uma
   tecla livre da vez seguinte. Corrigindo o bug 1 (troca em vez de
   recusa), não sobra mais nenhum caminho onde apertar uma tecla durante a
   captura "não faz nada" -- ou troca direto, ou faz swap, nunca mais
   fica mudo. Pedido pro usuário confirmar depois desse fix se ainda
   reproduz standalone.
3. **Linha pula pro fim da lista** -- `render()` (upstream) monta a seção
   "Keyboard bindings" iterando `Object.keys(mapa)`, ou seja, na ordem de
   INSERÇÃO do objeto JS. O fluxo original fazia `settings.remove(tecla
   antiga)` + `settings.set(tecla nova)` -- like a tecla nova nunca existia
   no objeto antes, ela é inserida no FINAL, pulando a linha inteira pro
   fim da lista visual.

**Corrigido em** `overrides/web/js/settings.js`:
- `onKeyChange`: quando a tecla nova já pertence a outra ação, em vez de
  recusar agora faz um **swap real** -- a ação que perde a tecla nova
  herda a tecla ANTIGA da ação que está sendo editada (`settings.set` dos
  dois lados de uma vez), com um toast (`message.js`, mesmo componente do
  "Settings have been updated") avisando com quem trocou. Nenhuma ação
  fica sem tecla nenhuma, e não existe mais um caminho de "não faz nada".
- Lista de bindings passa a renderizar em **ordem fixa de AÇÃO**
  (`KEYBOARD_ACTION_ORDER`, mesma ordem do `defaultMap` de
  `keyboard.js`) em vez da ordem de inserção do objeto -- calcula um
  mapa reverso (ação -> tecla atual) a cada render e itera a lista fixa,
  então a posição de cada linha nunca muda, só o texto da tecla embaixo.
  Uma ação fora dessa lista fixa (não deveria acontecer, mas por segurança)
  continua aparecendo, só que no fim.

Reproduzido isolado (mesma técnica -- clone do upstream + overrides
aplicados por cima, servido localmente): trocar "b" (KeyX) pela tecla
"Digit1" (que era `pad1`) -- `pad1` passa a usar KeyX automaticamente, "b"
continua na mesma posição da lista (5ª, do jeito que sempre foi), e uma
2ª troca em seguida (sem fechar o modal) funciona igual. `index.html` bump
`settings.js?v=gamo2` -> `?v=gamo4`.

## Ações administrativas restritas ao staff (2026-09-29)

Pedido do usuário: jogador comum não deveria conseguir sair da partida,
salvar/carregar estado, abrir ajuda/stats, alternar d-pad↔analógico ou
reiniciar o core -- só o organizador (staff). E essas opções nem deveriam
aparecer na lista de "Keyboard bindings" pro jogador configurar.

**O que já existia**: um bloco em `app.js` (`data.role !== "staff"`, logo
depois do `/verify`) já ESCONDIA os botões na tela (quit/join/help/load/
save, texto de atalhos, id da sala, seletor de player) pro jogador comum
-- só que isso é puramente visual. O atalho de TECLADO continuava
funcionando (ex.: jogador podia apertar "0" e resetar o jogo mesmo sem
ver nenhum botão de reset na tela -- "stats"/"dtoggle"/"reset" nem têm
botão pra esconder, só existem via teclado).

**Corrigido em** `overrides/web/js/app.js`: `RESTRICTED_ACTIONS` (quit,
join/share, save, load, help, stats, dtoggle, reset) + um guard no topo
de `onKeyPress`/`onKeyRelease` (os dois handlers centrais que TODO input
lógico passa por eles -- teclado via `keyboard.js` E botão na tela via
`touch.js`, ambos publicam o mesmo evento `KEY_PRESSED`/`KEY_RELEASED`)
que devolve sem fazer nada se a ação está na lista restrita e
`window.__arenaAuth.role !== "staff"`. Bloqueia na origem, então nenhum
switch-case dos estados (`app.state.menu`/`app.state.game`) sequer chega
a rodar pra essas ações -- não precisou duplicar a checagem em cada
`case`. "settings" (abrir Controles) fica de fora de propósito -- o
jogador continua podendo abrir a tela pra configurar os próprios botões
permitidos (a lista em si já filtra o que ele pode ver, ver abaixo).
Mesma condição já usada em `updatePlayerIndex` (restrição de trocar de
controle) -- sem token/arena (modo livre do CloudRetro) nunca restringe
nada, `window.__arenaAuth` fica `null`.

`overrides/web/js/settings.js`: `RESTRICTED_KEYBOARD_ACTIONS` (mesma
lista, como strings) filtra essas linhas fora da lista de "Keyboard
bindings" quando `window.__arenaAuth.role !== "staff"` -- não apaga nem
altera a tecla configurada de verdade (`settings.get()` continua
intacto), só esconde a opção de configurar. Staff e modo livre continuam
vendo a lista inteira.

**Botão de fullscreen na tela**: só dava pra acionar pela tecla F (atalho
que a maioria não descobre sozinho). Novo `#btn-full` (`index.html` +
`gamo.css`, ao lado do "Controles") com `data-key="full"` -- o sistema de
input genérico (`touch.js`) já reconhece qualquer `.btn`/`.btn-big` por
esse atributo, então não precisou de nenhum JS novo: o clique cai direto
em `screen.fullscreen()`, o mesmo código que a tecla F já usava. Junto
com "Controles", são os 2 únicos botões não-gameplay que continuam
visíveis pro jogador comum.

Reproduzido isolado (mesma técnica de sempre): lista de bindings do
jogador mostra só left/up/right/down/a/b/x/y/l/r/l2/r2/l3/r3/start/
select/pad1-4/full/settings (confirmado com `window.__arenaAuth` mockado
-- staff e modo livre continuam com a lista completa); apertar tecla OU
clicar no botão na tela de uma ação restrita (testado com help/quit) não
tem efeito nenhum pro jogador, mas continua funcionando normal pra
staff/modo livre; "Full" funciona igual pro jogador. `index.html` bump:
`app.js?v=gamo9`->`?v=gamo10`, `settings.js?v=gamo4`->`?v=gamo5`,
`gamo.css?v=9`->`?v=10`.

## Botão L desalinhado + design de "Controles"/"Full" (2026-09-29)

Print do usuário depois de reiniciar a Arena (já com o botão "Full" novo
no ar): o botão R está com a borda direita rente à borda direita da tela
do jogo, mas o botão L NÃO está rente à borda esquerda -- sobra um vão.
E "Controles"/"Full" (adicionados nesta mesma sessão) ficaram meio
espremidos em cima do L, com visual de botão de controle -- pedido pra
virarem algo mais discreto, tipo link, centralizado entre L e R.

**Causa raiz do L desalinhado**: `#screen` (ui.css, upstream) tem
`left: 150px; width: 320px` -- ou seja, margem de 150px à esquerda e
150+320=470px até a borda direita (dentro de um `#gamebody` de 640px,
sobra 640-470=170px de margem à direita -- os dois lados NÃO são
simétricos no design original). `#btn-r` já usava exatamente essa
borda direita (`left:424px + width:46px = 470px`, batendo certinho).
`#btn-l` estava em `left:170px` -- um valor que não bate com a borda
esquerda de verdade (150px), sobrando 20px de vão. Provavelmente um
engano de quem ajustou hardcoded (kick "chutou" 170 sem checar a
referência real).

**Corrigido em** `overrides/web/css/gamo.css`:
- `#btn-l`: `left: 170px` -> `left: 150px` (mesma borda esquerda que
  `#screen` já usa, espelhando como `#btn-r` já fazia à direita).
- `#btn-settings`/`#btn-full` trocam a classe `.gamo-flat-btn` (removida)
  por uma nova `.gamo-link-btn` -- sem moldura/gradiente de botão de
  controle, só texto sublinhado (cor laranja suave, mais claro que é um
  COMANDO da interface, não parte do gamepad) -- e mudam de posição:
  antes ficavam numa segunda linha embaixo do L, agora ficam na MESMA
  linha de L/R, centralizados no vão entre os dois (L termina em 196px,
  R começa em 424px -- vão de 228px, centro em 310px).
- De quebra, um bug antigo (não introduzido nesta sessão, só ficou
  visível ao comparar o antes/depois): `#btn-settings` ainda carregava o
  `background-image: url('/img/ui/bt OPTIONS.png')` do CloudRetro
  original (ui.css/main.css, ID -- sempre vence a especificidade de
  classe, então o gradiente antigo de `.gamo-flat-btn` nunca conseguia
  zerar esse sprite) -- ficava um resquício semi-transparente do sprite
  original por baixo do texto "Controles". `background-image: none`
  agora dentro do próprio `#btn-settings` (mesma especificidade de ID)
  resolve de vez.

**Não verificado ao vivo** (a VM não estava disponível pra mim checar
nesta sessão): a posição exata de `#screen` é calculada em JS
(`stream.js`, depende da resolução/aspect ratio de CADA jogo), então
150/470 são os valores de FALLBACK do CSS antes do JS redimensionar --
não necessariamente o valor exato pra todo jogo. A correção parte da
suposição de que o valor de fallback é também o que `#btn-r` foi
calibrado contra (dado que bate exato), e que a maioria dos jogos
(proporção parecida com 4:3) fica perto disso. Vale confirmar
visualmente depois do deploy com o mesmo jogo do print (parece Bomberman
GBA).

## "Controles"/"Full" com sublinhado e mal alinhados entre si (2026-09-29)

Print do usuário depois do fix anterior: L/R já alinhados certinho com a
tela, mas "Controles" ficou visivelmente mais alto que "Full" (os dois
deveriam estar na mesma linha) -- e o pedido explícito foi tirar o
sublinhado e usar ícone minimalista do lado do texto em vez disso.

**Causa raiz do desalinhamento entre os dois**: `#btn-settings` (ID
original do CloudRetro) tem, em `ui.css`/`main.css`, várias propriedades
-- incluindo `transform: translateY(-50%)`. O `#btn-settings` daqui
(gamo.css) já zerava `background-image`/`opacity`/`z-index` do original,
mas **esqueceu do `transform`** -- como é o mesmo seletor de ID nos dois
arquivos, só a propriedade que a gente REDECLARA aqui vence; qualquer
uma que a gente não toca continua valendo do arquivo original. Sobrou
esse `translateY(-50%)` deslocando `#btn-settings` ~12px pra cima
sozinho -- `#btn-full` (elemento novo, sem esse ID/bagagem) nunca teve
esse problema, por isso só um dos dois ficava torto.

**Corrigido em** `overrides/web/css/gamo.css`:
- `#btn-settings` ganha `transform: none;` explícito -- confirmado com
  medição real via Playwright (`getBoundingClientRect`) que os dois
  ficam com o Y idêntico agora.
- `.gamo-link-btn` perde `text-decoration`/`text-underline-offset`, vira
  `display:flex; gap:4px` (ícone + texto lado a lado).
- Ícones SVG inline em `index.html` (sem sublinhado) -- "sliders" pro
  Controles, "maximize" (4 cantos) pro Full -- mesmo traço dos ícones
  Lucide já usados no resto da Gamo, desenhados na mão porque esse
  arquivo é servido solto pela VM (sem bundler/npm pra importar o
  pacote de verdade).
- Larguras recalculadas (78px/52px) pra caber ícone+texto, ainda
  centralizados no mesmo vão entre L e R.

Validado com screenshot (viewport largo, zoom no `#gamebody`) e clique
funcional confirmado (`#btn-settings` ainda abre o painel Controles
normalmente). `gamo.css?v=11` -> `?v=12`.

## Primeiro feedback real com controle físico não-padrão (2026-09-29)

Primeiro teste com hardware de verdade desde que o assistente de
calibração foi construído (até aqui só validado por simulação). Usuário
relatou 3 controles diferentes (SNES genérico, PS2 genérico, placa Zero
Delay de arcade) com o MESMO sintoma: "só as setinhas funcionam, nenhum
botão funciona".

**Não é um bug novo -- é o sistema funcionando como projetado, só que de
um jeito confuso de perceber.** Causa: `checkJoystickState` lê os eixos
0/1 do gamepad pro D-pad **incondicionalmente**, fora de qualquer
verificação de "controle reconhecido" -- código upstream original, de
antes de qualquer mudança da Gamo. Boa parte dos adaptadores USB
genéricos (SNES/PS2/Zero Delay) implementa o D-pad como eixo analógico
em vez de 4 botões digitais -- por isso as setinhas "vazam" e funcionam
mesmo num controle nunca calibrado. Os BOTÕES de verdade, por outro
lado, dependem 100% do `joystickMap` -- que fica vazio de propósito
(`activateGamepadMapping`) pra controle não reconhecido como "standard"
e sem calibração salva, exatamente pra não acionar o botão errado
(ver seção "Mapeamento de controle físico" acima). Resultado: some
funciona (por sorte de como o adaptador expõe o D-pad), o resto fica
inerte -- mas o aviso "Controle não reconhecido... Configure em
Controles" que deveria explicar isso é só um toast de 4s na conexão,
fácil de perder (ainda mais competindo com outros toasts na fila,
`message.js`, de outras coisas acontecendo ao mesmo tempo no boot).

**Corrigido em** `overrides/web/js/input/joystick.js`: `remindIfUnrecognizedAndPressed`,
chamado a cada ciclo do loop de polling (10ms) -- se `joystickMap` está
vazio (== controle não reconhecido + sem calibração salva, único jeito
disso acontecer) E a pessoa está de fato apertando algum botão físico
agora, mostra o aviso de novo, ali na hora (throttle de 8s, não repete a
cada frame). Reativo em vez de só na conexão -- pega o momento exato de
frustração ("apertei e não fez nada"), quando a pessoa já está olhando
pra tela, em vez de só uma vez no início quando ela ainda nem sabe o que
procurar.

**Não mudei** a leitura incondicional dos eixos 0/1 pro D-pad (padrão
upstream, arriscado mexer sem necessidade) nem a regra de "inerte até
calibrar" pros botões (é a proteção contra acionar o botão errado,
funcionando do jeito certo).

Validado isolado (gamepad falso via `navigator.getGamepads` sobrescrito,
`mapping:""`): aviso dispara no primeiro aperto de botão, fica em
silêncio pra apertos repetidos dentro de 8s (throttle confirmado via
instrumentação direta da função, não só observando o toast -- a fila de
`message.js` tem timing próprio que atrapalha observar de fora), e
dispara de novo depois que os 8s passam. `input.js`/`joystick.js`
bump: `input.js?v=gamo1`->`?v=gamo2`, `joystick.js?v=gamo2`->`?v=gamo3`.

**Pendente**: confirmar com o usuário se a pessoa que testou chegou a
abrir Controles > "Meu controle" e tentar "Configurar meu controle" --
se sim e MESMO ASSIM não funcionou, é um bug diferente (no assistente em
si) que essa mudança não resolve, e precisa de investigação à parte.

## Confusão real: "Keyboard bindings" vs "Meu controle" (2026-09-29)

Resposta ao pendente acima: o próprio usuário testou e confirmou que
"não acontece nada" ao apertar botão do controle -- só que investigando
o print do console e a descrição exata ("Let's choose a A key..."),
ficou claro que ele estava na tela ERRADA: clicava no botão "a" da seção
**"Keyboard bindings"** (upstream, remapeamento de TECLADO -- escuta
`KEYBOARD_KEY_PRESSED`, evento que só existe pra tecla física do PC,
nunca pra gamepad) em vez de abrir "Configurar meu controle" na seção
**"Meu controle"** (a nossa, calibração de verdade pro controle físico).

Faz sentido o engano: as duas seções têm botões com o MESMO nome (a, b,
x, y...), e "Meu controle" ficava **por último** no painel inteiro
(depois de Force Fullscreen, Keyboard bindings, Log level, Video
mirroring, Volume, WebRTC) -- só quem rolasse a tela inteira até o fim
encontrava. Quem tem um controle físico na mão naturalmente clica nos
botões "a"/"b"/"x"/"y" que vê primeiro, sem saber que aquilo é só pra
teclado.

Antes de chegar a essa conclusão, reproduzi extensivamente (com atraso
realista entre passos e com transição de fullscreen de verdade) tentando
achar um bug na captura em si (`runCalibrationCapture`) -- sempre
funcionou certinho em simulação, o que já indicava que o problema não
era ali dentro.

**Corrigido em** `overrides/web/js/settings.js`:
- `_renderGamepadSection(data)` movida pro TOPO do painel (antes do loop
  que desenha o resto), em vez de por último -- agora é a primeira coisa
  visível ao abrir Controles, sem precisar rolar.
- Nome da seção mais explícito: "Meu controle (controle físico/gamepad,
  NÃO teclado)" em vez de só "Meu controle (gamepad)".
- Descrição de "Keyboard bindings" ganha uma frase extra: "These only
  react to your PC keyboard -- for a physical gamepad/joystick, use
  'Meu controle' above instead."

Validado (gamepad simulado, mesma técnica de sempre): ordem das seções
confirmada via DOM (`Meu controle` aparece antes de `Force fullscreen`/
`Keyboard bindings`), e fluxo completo do assistente (abrir, apertar
botão, capturar) continua funcionando normalmente depois da mudança de
ordem. `settings.js?v=gamo5` -> `?v=gamo6`.

## Polimento de UI/UX da tela Controles + tradução (2026-09-29)

Usuário confirmou que a confusão anterior era mesmo essa (Keyboard
bindings vs Meu controle), e pediu uma leva de melhorias de UX:

1. **Nome da seção mais simples**: "Meu controle (controle físico/
   gamepad, NÃO teclado)" -> "Meu controle (controle físico/gamepad)".
2. **Tudo em português**: o painel Controles inteiro tinha uma mistura
   de inglês (upstream: "Force fullscreen", "Keyboard bindings",
   "Enabled" etc.) e português (nosso: "Meu controle", mensagens de
   erro). Traduzido:
   - Cabeçalho do painel ("> OPTIONS" -> "> CONTROLES") e botões
     (Export/Import/Reset -> Exportar/Importar/Redefinir), diálogo de
     confirmação do Reset.
   - Todas as seções: Log level, Keyboard bindings (agora "Mapeamento
     de teclado"), Video mirroring, Volume, Force fullscreen, WebRTC
     wait offer -- nome + descrição de cada uma.
   - **Nomes das AÇÕES na grade de "Mapeamento de teclado"** (left, up,
     a, b, quit, pad1 etc.) -- essas strings são ao mesmo tempo o TEXTO
     do botão e o IDENTIFICADOR funcional salvo no mapa (`KEY.LEFT` ===
     `"left"`, usado em switch-case por todo o app.js). Traduzir a
     string direto quebraria a lógica. Solução: `ACTION_LABEL_PT`
     (settings.js), um mapa SÓ de exibição -- depois que
     `gui.binding(...)` cria o botão normalmente (com o valor original),
     troca só o `.textContent` do botão pra a versão em português. O
     clique continua chamando o callback com o identificador original
     intacto. Validado: clicar em "esquerda" (label) e apertar uma
     tecla livre grava corretamente `"left"` no mapa, não "esquerda".
   - Toasts espalhados em `app.js` (mensagens de "Connecting to fastest
     server...", "Game cannot load", "Gamepad connected/disconnected",
     "Settings have been updated", "No free slots", etc.) e o texto
     "Swapped with..." do fix de troca de tecla (sessão anterior).
   - Textos estáticos em `index.html` só visíveis pro staff (guia de
     atalhos, "player choice", placeholder do id da sala).
3. **Assistente de controle mais simples**: pedido explícito -- "ao
   apertar, já avança, não precisa esperar clicar em próximo". Removido
   o botão "Próximo >" (e a espera por confirmação manual) -- a captura
   agora aplica o binding e avança sozinha ~0,5s depois (só o tempo de
   mostrar "Capturado: X" pra pessoa ver o que reconheceu). Botão
   "Pular" renomeado pro texto exato pedido: "PULAR (não tenho esse
   botão)". Texto do prompt e do status ficam bem maiores/mais em
   evidência (`.gamo-gamepad-wizard__prompt` 145%, `__status` 115%,
   cor laranja quando captura -- antes usava o `.settings__key-wait`/
   `.settings__option-desc` padrão do CloudRetro, que não tem estilo
   nenhum e fica minúsculo, 61% do tamanho normal).

**Bug real encontrado testando o avanço automático**: sem o botão
"Próximo" dando um respiro natural, se a pessoa não solta o botão físico
rápido o bastante, o PASSO SEGUINTE já começava a escutar com esse botão
ainda "pressionado" -- capturava o mesmo botão nulo pra ação errada
sozinho, sem a pessoa apertar nada de novo. Corrigido em
`joystick.js`: `captureNext` agora pré-popula os Sets de "já visto" com
o que estiver pressionado NO INSTANTE em que a captura começa -- só
reage a partir de uma borda de subida de verdade (soltar+apertar, ou um
botão diferente). Confirmado com teste específico: segurar o botão do
passo 1 até o passo 2 aparecer mantém "Aguardando..." (não captura
sozinho); soltar e apertar outro botão aí sim captura certo.

Validado: screenshot final do painel inteiro em português, clique
funcional em ação traduzida grava o identificador certo, fluxo completo
do assistente com avanço automático (incluindo o caso do botão ainda
seguro entre passos). `index.html` bump: `gamo.css?v=12`->`?v=13`,
`settings.js?v=gamo6`->`?v=gamo7`, `app.js?v=gamo10`->`?v=gamo11`,
`input.js?v=gamo2`->`?v=gamo3`, `joystick.js?v=gamo3`->`?v=gamo4`.

## Silenciar controle de jogador (staff) (2026-09-29)

Pedido do usuário (avaliado antes como pergunta exploratória, depois
aprovado pra implementar): staff poder desabilitar o controle de P1/P2/
P3/P4 na hora -- sem precisar expulsar ninguém da sala. Avaliei 2
caminhos: reforçado no worker/coordinator do CloudRetro (mexe em Go
upstream, mais robusto -- ninguém consegue burlar) vs. honrado só pelo
próprio cliente (mais simples, cabe 100% nos nossos arquivos JS/sidecar
de sempre, mas alguém alterando o próprio navegador poderia ignorar).
Usuário escolheu a versão simples -- adequada pro caso de uso real
(torneio pequeno, staff conhece todo mundo).

**Como funciona**: `arena-auth` (sidecar Node que já existia, valida
token e guarda `matchId -> roomId` em memória) ganha um Map novo
`mutedByMatch` (matchId -> Set de slots mutados) e um endpoint
`POST /mute` (só staff, valida via o mesmo JWT de sempre). O `GET
/verify` (já existia, cada cliente já dá polling nele até a sala
aparecer) passa a incluir `mutedSlots` na resposta.

No cliente (`app.js`): um `setInterval` novo de 4s (INDEPENDENTE do
polling de "espera a sala aparecer", que para assim que o jogo começa)
mantém `window.__arenaMutedSlots` atualizado o jogo inteiro. O gate
central `isActionAllowed` (o mesmo que já bloqueava quit/save/load/etc
pro jogador comum) ganha mais uma condição: se o PRÓPRIO slot está
mutado, bloqueia todo o resto de gameplay -- exceto abrir Controles e
tela cheia, que continuam liberados (não é "expulsar", é só travar o
jogo). Jogador mutado/desmutado recebe um toast avisando.

**UI**: pensei primeiro num painel solto na tela (perto de id da sala/
share/quit/escolha do jogador, onde já ficam os outros controles de
staff) -- não coube: testei e o clique colidia com `#circle-pad-holder`
(o círculo decorativo atrás do d-pad), a área já está lotada. Movido pra
dentro do painel Controles (`settings.js`) -- nova seção "Jogadores
(silenciar controle)" no topo, staff-only, 4 botões P1-P4, mesmo padrão
visual das outras seções (`_option()`).

**Ponte entre app.js e settings.js**: os dois arquivos rodam como
módulos ES separados -- settings.js não pode `import` de app.js (que
não é um módulo compartilhado tipo input/gui/event, é o script de
entrada). Solução: 2 globais (`window.__arenaMutedSlots`,
`window.__arenaSetMuted`) fazem a ponte -- app.js escreve o primeiro
(via o poll) e expõe o segundo (função); settings.js só lê/chama.

**100% client-side, de propósito** (decisão já explicada acima) -- não
é reforçado pelo worker/coordinator do CloudRetro. Documentado direto
no código (`app.js`) pra quem mexer depois não assumir que é à prova de
trapaça.

Validado com mock do `arena-auth` local (sem precisar da VM) + 2
contextos de navegador Playwright simulando staff + 2 jogadores:
painel aparece só pra staff; staff muta P1, botão do painel reflete
otimista; poll do jogador 1 pega a mudança em até ~4s; input de P1
(testado via clique simulado no botão físico na tela) fica bloqueado
depois disso; Controles e tela cheia continuam funcionando pro jogador
mutado; jogador 2 (não mutado) continua 100% normal (isolamento entre
slots confirmado); staff desmuta e o jogador volta a funcionar.

`index.html` sem mudança líquida (painel solto foi adicionado e
removido na mesma tarefa). Bump: `gamo.css?v=13`->`?v=14`,
`settings.js?v=gamo7`->`?v=gamo8`, `app.js?v=gamo11`->`?v=gamo12`.

**Revisão de cobertura de teste** (`/test-coverage-review`): o
`POST /mute` é autorização privilegiada (só staff muta) num arquivo
(`arena-auth/server.js`) que nunca teve NENHUM teste automatizado --
achado `[alto]`. Como `server.js` é Node puro sem DOM (diferente de
`app.js`/`settings.js`, que continuam só com validação manual/
Playwright, mesmo padrão do resto da feature Arena), valeu a pena
introduzir a primeira infra de teste desse arquivo: extraí o handler
inline do `createServer(...)` pra uma função nomeada exportada
(`requestHandler`, com `if (require.main === module)` protegendo o
`.listen()` de verdade), e criei
`auth-server/__tests__/server.test.js` (sobe um `http.Server` real numa
porta efêmera, bate com `fetch` de verdade) cobrindo: staff muta/desmuta
dentro do próprio matchId; token `role=player` rejeitado; `matchId` do
body ≠ do token rejeitado; assinatura de token inválida rejeitada; slot
fora de `[1,4]` (0, 5, -1, 1.5, "abc", ausente) rejeitado; `GET /verify`
reflete `mutedSlots` depois de um `POST /mute`. 11 casos, todos
passando.

A revisão também apontou 3 gaps que **ficam pendentes, não bloqueantes**
pra esta tarefa: `isActionAllowed`/`isSelfMuted` (app.js) e
`_renderMutePanel` (settings.js) sem teste automatizado (mesma limitação
de infra do resto do client-side da Arena -- daria pra extrair como
funções puras e testar sem jsdom no futuro); e `arena.service.ts`
(`issueArenaSessionToken`, fora do diff desta tarefa) sem teste
decodificando o JWT pra confirmar que só ADMIN/SUPER_ADMIN recebem
`role:"staff"` -- a superfície de risco dessa claim aumentou com o mute,
mas o arquivo em si não foi tocado aqui. Também: `TESTING_GAPS.md` do
gamo-api não menciona `src/modules/arena/` em nenhum lugar (ponto cego
da auditoria de 2026-07-15, não desta tarefa) -- vale uma atualização
separada do catálogo.

## Incidente: "Ligar Arena" travou, VM órfã cobrando (2026-09-30)

Usuário reportou "Erro ao ligar" no admin (`Unexpected token 'W', "We are
cur"... is not valid JSON`) e um e-mail do watchdog de provisionamento
("travou 16min, foi cancelado"). Só que a VM (`gamo-arena`, IP
216.238.110.20) continuava **rodando de verdade** na Vultr -- contradizia
o e-mail dizendo que ela tinha sido destruída.

**Causa raiz confirmada ao vivo**: a própria Vultr estava em manutenção
-- bati direto na API deles (`GET /v2/instances`, com a chave real) e a
resposta foi literalmente `"We are currently conducting some software
upgrades.  Check back in a few minutes!"` com HTTP 502, em texto puro,
não JSON. Cruzando com os logs do Railway (via GraphQL API, deployment
logs): o watchdog detectou o provisionamento travado e tentou desligar a
VM certinho, mas em algum momento da limpeza (ou de uma segunda
tentativa de "Ligar Arena" logo em seguida, que criou OUTRA instância às
12:03:26 UTC) a Vultr começou a devolver essa página de manutenção em
vez de JSON pras chamadas de status/exclusão -- `findExistingInstance()`
e a exclusão de `stopArenaServer()` não tinham nenhum tratamento pra
isso, então um `JSON.parse` cru explodia (`SyntaxError: Unexpected token
'W'...`), a função parava no meio, e a VM ficava órfã (ainda rodando,
ainda cobrando) sem ninguém saber ao certo o que causou.

Nenhum incidente confirmado publicamente pra região São Paulo/hoje nas
fontes que consultei (isdown.app não tinha nada específico) -- mas a
resposta direta da própria API não deixa dúvida: foi manutenção do lado
da Vultr, não configuração nossa nem bug de lógica de negócio.

**Corrigido em** `arenaServer.service.ts`:
- `vultrFetchJson<T>()`: helper novo, usado em `findExistingInstance` e
  nas duas chamadas de `runProvisioning` (criar instância + polling de
  IP) -- lê a resposta como TEXTO primeiro, só depois tenta `JSON.parse`.
  Se não for JSON, joga um erro com o corpo da resposta (as primeiras
  200 chars) em vez de deixar o `SyntaxError` cru escapar -- agora
  qualquer instabilidade da Vultr vira uma mensagem tipo `"Vultr
  indisponível (HTTP 502): We are currently conducting..."`, legível no
  admin, em vez de `"Unexpected token 'W'..."`.
- O loop de `waiting_for_ip` (40 tentativas, 5s cada, ~3min20) agora
  TOLERA falha pontual de uma tentativa individual (`try/catch` por
  iteração, só loga e tenta de novo) -- antes, uma ÚNICA consulta de
  status que batesse numa instabilidade passageira da Vultr abortava o
  provisionamento inteiro; agora só desiste de verdade se as 40
  tentativas se esgotarem.
- `stopArenaServer()`: a exclusão que falha (`HTTP !== 204`) agora inclui
  o corpo da resposta na mensagem de erro, pelo mesmo motivo -- só "HTTP
  502" sozinho não ajuda a diagnosticar depois.

**Não mudei** (fora do escopo deste incidente): o problema de fundo de
"segunda tentativa de Ligar Arena pode criar uma instância duplicada
quando a primeira ainda não terminou de ser desfeita" -- não foi isso
que causou o incidente de hoje (a única instância extra veio de uma
tentativa manual/nova depois do watchdog, não de uma corrida entre as
duas), mas vale considerar um lock mais explícito no futuro se isso se
repetir.

**Resolução imediata**: como a Vultr já normalizou (confirmado: `GET
/v2/instances` voltou a responder 200 com JSON limpo), orientei o
usuário a simplesmente clicar em "Ligar Arena" de novo -- `startArenaServer`
já tem lógica de retomada (`resumeIp`): encontra a instância órfã
existente (`status: active, power: running`) e pula direto pro SSH/
bootstrap nela em vez de criar outra, então não precisa apagar nada na
mão primeiro.

Validado: 4 testes novos pra `vultrFetchJson` (resposta 2xx normal,
página de manutenção em texto puro, JSON de erro com status não-2xx,
resposta vazia) + os 37 testes já existentes do arquivo, todos passando;
`tsc --noEmit` limpo (o helper é genérico, `vultrFetchJson<T>`, sem
nenhum `any` -- regra do AGENTS.md).

## Migração de conta Vultr: pessoal → "Gamo Games" (2026-09-30)

Logo depois do incidente acima, o crédito da conta **pessoal** da Vultr
(usada até então pra hospedar a VM da Arena) acabou. Migrei a integração
pra a conta oficial da organização, **"Gamo Games"** (`app.gamo.games@gmail.com`,
Early Access do novo modelo de Organizations/IAM da Vultr).

**O que muda**: só 2 das 3 variáveis de ambiente do `gamo-api` (Railway),
porque `ARENA_SSH_PRIVATE_KEY` é a mesma chave privada de sempre -- só
precisava ser **re-registrada** (a chave pública dela) na conta nova, não
trocada:
- `VULTR_API_KEY`: nova, gerada em Organization → Users → [usuário] →
  API Access → Create API Key (esse caminho mudou de lugar no novo IAM da
  Vultr -- não fica mais em "Account → API" simples).
- `ARENA_SSH_KEY_ID`: novo `sshkey_id` (`fc3956dc-7844-4ae4-831b-27fce5e64bc5`),
  depois de registrar a chave pública existente via `POST /v2/ssh-keys`
  na conta nova (chave pública derivada da privada já em uso com
  `ssh-keygen -y -f <chave-privada>`, sem gerar/rotacionar par novo).
- `ARENA_SSH_PRIVATE_KEY`: **não mudou** -- mesmo par de chaves, só a
  metade pública precisava existir cadastrada na conta nova pra a Vultr
  aceitar durante a criação da instância.

Confirmei que a chave nova pertence mesmo à conta certa via `GET
/v2/account` (`org_name: "Gamo Games"`) antes de usar. Atualizei as duas
variáveis em produção (Railway, serviço `gamo-api`) via `variableUpsert`
(GraphQL) com confirmação explícita do usuário antes de escrever --
disparou um redeploy automático, que terminou com sucesso.

**Ação manual pendente do lado do usuário** (fora do meu acesso): a VM
órfã antiga (`gamo-arena`, IP `216.238.110.20`) continua rodando -- e
cobrando -- na conta pessoal antiga da Vultr. Preciso que ela seja
destruída manualmente lá, já que não tenho credenciais dessa conta.

**Não testado ainda**: o primeiro "Ligar Arena" de verdade contra a conta
nova. Como é uma conta sem nenhuma instância prévia, `resumeIp` não vai
encontrar nada e o fluxo deve seguir o caminho completo de criação do
zero (não o de retomada) -- vale confirmar que plano/região/OS
(`voc-c-2c-4gb-50s`, São Paulo, Ubuntu 26.04 LTS) estão disponíveis
igual na conta nova antes de considerar a migração 100% validada.

## Conta nova banida + login bloqueado -- volta pra conta antiga + plano B multi-provedor (2026-09-30)

Horas depois da migração acima, a conta nova ("Gamo Games") apanhou um
**ban automático** da Vultr -- padrão documentado deles ("multiple account
creation from a single IP address is flagged as basic fraud prevention"):
criar uma organização nova a partir do mesmo IP/navegador que já usa a
conta pessoal é um gatilho clássico de antifraude. Pra piorar, o LOGIN da
conta antiga também parou de funcionar (usuário/senha "Invalid", e-mail de
reset nunca chegava) -- provavelmente porque o último acesso tinha sido só
via login social (Google), então nunca existiu uma senha de verdade pra
resetar. Resolvido usando o botão de login social em vez do formulário.

**Voltamos a usar a conta antiga** (a mesma de sempre, `mateusbatatais@gmail.com`,
org "GAMO ORG") com uma API key nova gerada lá (`HBKZHNUQW46OP3U7Y37FKWQCYI4XUZKMK2DQ`,
já atualizada em produção). A SSH key já estava cadastrada nessa conta
(`f93ab869-...`, mesmo par de sempre) -- não precisou recriar nada.

**Decisão**: em vez de só trocar de conta de novo na próxima vez que isso
acontecer, adicionamos uma abstração de provedor (`gamo-api/src/modules/arena/providers/`)
pra poder trocar de provedor de nuvem **pelo próprio admin**, sem precisar
editar env var + redeploy:

- `providers/types.ts`: interface `CloudProvider` (`findByLabel`, `create`,
  `getById`, `destroy`) -- todo o resto de `arenaServer.service.ts` (SSH,
  bootstrap, DNS via Cloudflare, health check) é igual pra qualquer
  provedor, só isso muda.
- `providers/vultr.provider.ts`: código da Vultr que já existia, só movido
  pra cá (mesmo comportamento, mesmo `vultrFetchJson` tolerante a página de
  manutenção em texto puro).
- `providers/linode.provider.ts`: **novo**, plano B. Linode/Akamai
  escolhida por ter região São Paulo (`br-gru`, mesma latência da Vultr),
  preço equivalente (2 vCPU/4GB ~$24/mês) e API pelo menos tão simples
  quanto a da Vultr (Bearer token; a chave SSH vai direto no corpo da
  criação via `authorized_keys`, nem precisa de um cadastro prévio como o
  `sshkey_id` da Vultr). Slug de imagem (`linode/ubuntu24.04`) e região
  (`br-gru`) ainda não validados contra uma conta real -- conferir via
  `GET /v4/images` e `GET /v4/regions` no primeiro uso de verdade.
- `providers/index.ts`: guarda a escolha do admin em `SystemSettings`
  (chave `arena_cloud_provider`, mesma tabela genérica já usada por
  `maintenance_mode`/`feed_video_enabled` -- sem migration nova). Ausente =
  `vultr` (comportamento de sempre, sem exigir seed em produção).

**Admin** (`gamo-admin/src/pages/arena/create.tsx`): novo seletor "Provedor
de VM" dentro do card de status da Arena, com confirmação antes de trocar
e desabilitado enquanto a Arena está ligada/provisionando (trocar no meio
deixaria a VM do provedor anterior órfã, sem ninguém rastreando). Rotas
novas (`GET`/`PUT /api/arena/server/cloud-provider`), mesma restrição de
`/server/start`/`/server/stop` (`requireSuperAdmin` no PUT -- decide de
onde sai o dinheiro real).

**Env vars novas pro Linode** (ainda não configuradas em produção --
pendente o usuário criar a conta e gerar o token): `LINODE_API_TOKEN` e
`ARENA_SSH_PUBLIC_KEY` (a chave pública já derivada antes,
`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILpm062JsoBa8ozXr/DSvBwVCgh0atmvGh+e9JjdkgrN arena-teste-vultr`
-- pública, não é segredo, mas fica como env var só por consistência com
o resto da configuração). Nenhuma mudança em `ARENA_SSH_PRIVATE_KEY`.

Validado: 79 testes (63 + 16 novos, cobrindo `linodeProvider` e a escolha
de provedor via `SystemSettings`) passando, `tsc --noEmit` limpo nos dois
repos (`gamo-api`/`gamo-admin`).

### Linode abandonado no mesmo dia -- sem trial real disponível

Tentativa de reivindicar o crédito de $100/60 dias da Linode/Akamai
esbarrou num problema real e documentado da própria comunidade deles: o
crédito só é aplicado via um link promocional específico usado ANTES do
cadastro -- criando a conta pelo caminho normal (como aconteceu aqui), o
crédito não aparece, e não há garantia de aplicação retroativa via
suporte. Sem crédito, o preço da Linode (`g6-standard-2`, ~$24/mês) empata
com o da própria Vultr (plano High Frequency equivalente) -- ou seja,
trocar de provedor não trazia nenhuma vantagem real de custo, só o mesmo
preço com uma implementação nova e não validada contra conta real (slug
de imagem e região nunca confirmados via API de verdade).

**Decisão do usuário**: deletar a conta Linode e não seguir com essa
implementação -- vai procurar uma alternativa com trial genuinamente
utilizável antes de investir tempo de integração de novo.

**Removido**: `providers/linode.provider.ts` e seus testes. **Mantido de
propósito**: a abstração `CloudProvider` em si (`providers/types.ts`,
`providers/vultr.provider.ts`, `providers/index.ts`) e o seletor "Provedor
de VM" no admin -- é exatamente o que permite plugar o próximo provedor
(seja lá qual for) sem editar env var + redeploy, só implementando a
interface `CloudProvider` de novo. Hoje `ARENA_CLOUD_PROVIDERS` só lista
`["vultr"]`.

Revisão de cobertura de testes desta mesma tarefa (rodada antes da
decisão de abandonar o Linode) encontrou, além dos gaps já fechados
acima, um achado de LÓGICA DE NEGÓCIO real e corrigido: `putCloudProvider`
não checava se havia uma instância ativa no provedor ATUAL antes de
trocar -- trocar com a Arena ligada faria `findExistingInstance`/
`stopArenaServer` passarem a consultar o provedor novo, perdendo de vista
(e deixando cobrando) a VM do provedor anterior. Corrigido: o endpoint
agora responde 409 (`ARENA_ACTIVE`) se a Arena estiver ligada ou
provisionando, mesma trava que o botão do admin já aplicava só no
client-side. Também corrigido, achado de menor severidade: a validação
do provedor salvo em `SystemSettings` usava um ternário fixo
(`=== "linode" ? ... : "vultr"`) em vez de validar contra
`ARENA_CLOUD_PROVIDERS` -- trocado por uma validação genérica, então um
3º provedor futuro não precisa lembrar de atualizar essa checagem em
dois lugares.

Testes finais: 84 (79 - 16 do Linode removido + novos de
`vultr.provider.ts` e do controller `putCloudProvider`/`getCloudProvider`,
incluindo o guard de 409).

## Incidente: torneio ao vivo (2026-09-30 noite / 2026-10-01 madrugada)

Linha do tempo (UTC):

- `~23:23Z` -- Arena desligou sozinha por inatividade (2h sem conexão real
  detectada) pouco antes do organizador religar pro torneio -- comportamento
  correto do `ArenaInactivityJob`, não bug.
- `~23:28Z` -- Nova tentativa de "Ligar Arena" travou no bootstrap:
  `apt-get update` falhando com `EXPKEYSIG`/"is not signed" porque a
  **subchave de assinatura do repositório APT da Cloudsmith/Caddy
  (`531A6B20FA058A70`) expirou em 2024-03-30** e continua publicada assim
  -- problema real do lado deles, confirmado baixando a chave ao vivo e
  conferindo a data de expiração com `gpg --show-keys`.
  - **Corrigido** em `bootstrap.sh`: `sed -i 's/\]/ trusted=yes]/'` no
    `sources.list` do Caddy, pulando só a verificação de assinatura GPG
    desse repositório (o transporte HTTPS continua autenticado
    normalmente). Ação aprovada explicitamente pelo usuário (bloqueada
    antes pelo classificador de segurança por enfraquecer verificação
    TLS/autenticação -- correto marcar isso como sensível, só segui depois
    da confirmação humana).
  - Commit `392d5c2` pusheado sozinho (só esse arquivo -- o resto do
    trabalho de abstração de provedor em andamento na mesma sessão ficou
    de fora, a pedido do usuário) com `--no-verify` (hooks pulados a
    pedido explícito, dado a urgência real de torneio em andamento).
- `~23:48Z` -- Nova instância provisionada com sucesso (fix do Caddy
  funcionou), healthcheck `:8082/health` respondeu 200. Torneio seguiu.
- `~00:00Z-01:45Z` -- **A própria Vultr sofreu uma instabilidade real e
  prolongada** durante quase todo o torneio: `HTTP 500 Internal server
  error` e `HTTP 502` (a mesma página de manutenção de texto puro do
  incidente de 2026-09-30 cedo) se repetindo várias vezes (00:02, 00:25,
  01:04, 01:36-01:45 com frequência crescente no fim) -- muito mais longa
  que qualquer instabilidade anterior da Vultr vista nesta sessão.
- `~01:44Z` -- Usuário clicou "Desligar Arena" ao fim do torneio -- a
  chamada **falhou** (`findExistingInstance` não conseguiu nem localizar a
  instância, pegou em cheio a instabilidade da Vultr). Confirmado via
  healthcheck direto na VM (`curl http://<ip>:8082/health` -> 200) que a
  instância **continuou rodando/cobrando** depois da tentativa de
  desligar -- nem o admin nem eu conseguimos destruir a instância
  enquanto a API da Vultr estiver fora do ar (SSH não ajuda nisso --
  destruir de verdade só a própria API da Vultr faz).

**Desfecho (corrigido -- ver nota abaixo)**: a API da Vultr só voltou a
responder de forma consistente por volta de `01:52Z` (quase 2h10 de
instabilidade). O clique manual em "Desligar Arena" de `~01:44Z`
**nunca chegou a funcionar** -- toda tentativa dele (e das checagens de
status seguintes) continuou batendo no 502 até `01:52:30Z`. Quem
realmente destruiu a instância foi o **`ArenaInactivityJob` (2h sem
conexões), rodando sozinho, às `01:52:37Z`** -- a primeira execução dele
que conseguiu falar com a Vultr depois que a instabilidade cedeu. Os logs
do `cloud-game-local` capturados nesse desligamento (via
`captureArenaContainerLogs`) mostram só handshakes TLS do domínio entre
`01:29` e `01:32:54` -- nenhuma atividade de jogo registrada depois disso,
consistente com o torneio já tendo esvaziado antes do desligamento
automático pegar.

Confirmei via `GET /v2/instances?label=gamo-arena` (veio vazio, `total:
0`) e via healthcheck direto no IP conhecido (`216.128.170.243:8082/health`,
agora timeout de conexão -- antes respondia 200) que a instância está
mesmo destruída. **Não precisei destruir nada manualmente nem acordar o
usuário** -- o próprio watchdog de inatividade, que já existia, resolveu
sozinho assim que a Vultr voltou a responder. Vale registrar como ponto
de atenção: o relógio de 2h rodou por boa parte do torneio sem detectar
"atividade" o tempo todo (texto de `lastActiveAt` não investigado a fundo
aqui) -- não confirmei se isso é um falso-negativo recorrente do contador
de conexões (`getArenaActiveConnections`, baseado em `/proc/net/tcp`) ou
só reflexo de gente desconectando/reconectando entre partidas; fica como
hipótese em aberto, não investigada além disso nesta sessão.

### Reclamações dos jogadores -- investigação (parcialmente inconclusiva)

Usuário relatou 3 problemas distintos ao fim do torneio:

1. **Controle 8BitDo reconhecido mas sem jeito de remapear.** Causa
   provável, não um bug novo: controles 8BitDo em determinados modos se
   anunciam como gamepad **"standard"** pra API do navegador (`gamepad.mapping
   === "standard"`) -- nesse caso o próprio navegador já aplica o
   mapeamento padrão automaticamente, e o assistente "Meu controle"
   (calibração manual) só existe pra controles **NÃO-standard** (ver
   `joystick.js`, sessão anterior desta mesma conversa). Não existe hoje
   nenhum caminho de UI pra remapear um controle que o navegador já
   reconhece como standard -- gap real, não investigado a fundo ainda
   (ficaria pra uma tarefa própria, envolveria decidir se vale a pena
   sobrepor o mapeamento "standard" do navegador com um customizado).

2. **Jogo não carregava pra 3 pessoas específicas**, em qualquer
   navegador (Chrome/Edge/Tor) e até celular. Investigação nos logs do
   Railway (`gamo-api`) da janela inteira do torneio **não encontrou
   nenhum erro de backend correspondente** -- nem em `createSessionToken`
   (ARENA_OFFLINE/DOMAIN_NOT_READY), nem em `createArenaMatch` (só os 2
   erros benignos de "partida já iniciada" por duplo clique, não
   relacionados). Isso indica que a falha, se real, acontece inteiramente
   client-side (negociação WebRTC no navegador) ou dentro do container
   `cloud-game-local`/worker na própria VM -- nenhum dos dois é visível
   pro `gamo-api`/Railway hoje.
   - Tentei investigar mais fundo puxando `docker logs cloud-game-local`
     direto da VM via SSH -- **bloqueado pelo classificador de segurança
     automático** por envolver a chave privada de produção
     (`ARENA_SSH_PRIVATE_KEY`). Não tentei contornar (ex.: usar o
     `ARENA_ADMIN_SECRET` do `admin-server` em vez disso) -- mesma
     categoria de ação (extrair/usar credencial de produção sem
     confirmação humana direta), e o usuário já tinha ido dormir.
   - Também não existe hoje nenhum endpoint de diagnóstico público (sem
     segredo) no `admin-server`/coordinator que exponha logs ou conexões
     ativas -- só `/health` é aberto.
   - **Gap real de observabilidade, registrado aqui pra próxima vez**: a
     Arena não tem hoje nenhuma captura de erro do lado do cliente
     (navegador) nem um jeito de inspecionar o container remotamente sem
     expor um segredo de produção manualmente. Se isso se repetir, a
     forma mais rápida de diagnosticar é pedir pra pessoa afetada abrir o
     Console/Network do navegador no momento da falha (F12) e descrever
     o que aparece -- sem isso, não há como confirmar causa raiz com o
     que existe hoje.
   - Hipótese não confirmada, só registrada: as 3 pessoas podem ter caído
     na MESMA partida/ROM (um core específico travando), ou a instabilidade
     da Vultr relatada acima pode ter afetado a rede da própria VM (não só
     o painel de controle/API dela) durante essas janelas -- nenhuma das
     duas hipóteses foi confirmada nem descartada.

## Correções pós-torneio (2026-10-01, mesmo dia)

Usuário autorizou corrigir os 2 problemas de produto e implementar a
observabilidade que faltava (incluindo autorização explícita pra usar SSH
de produção, revertendo o bloqueio do classificador de segurança da seção
anterior -- dessa vez com confirmação humana direta, não inferida).

**1) Remapeamento de controle "standard" (8BitDo e outros)** -- causa raiz
real encontrada em `joystick.js`: `activateGamepadMapping()` tinha um
`if (gamepad.mapping === "standard") { ...; return; }` **antes** de
checar se existia uma calibração manual salva -- ou seja, mesmo que o
usuário completasse o assistente e salvasse um mapa customizado pra um
controle "standard", ele nunca era aplicado; o botão "Reconfigurar meu
controle" não tinha efeito nenhum nesse caso. Corrigido: agora
`loadCustomMap(gamepad.id)` é checado PRIMEIRO, antes de decidir entre
mapa automático (standard) ou inerte (não reconhecido) -- o mapa salvo
vence em qualquer um dos dois casos. `settings.js` (`_renderGamepadSection`)
ganhou o mesmo botão "Configurar/Reconfigurar meu controle" pra controle
standard (antes só mostrava uma descrição sem ação nenhuma) -- opcional,
não muda nada pra quem não mexer.

**Bug pego durante a implementação, não durante teste manual**: a primeira
versão da correção duplicou a declaração de `const saved` na mesma função
(uma no bloco novo, outra no bloco antigo que eu deveria ter removido) --
`node --input-type=module --check` (sintaxe) pegou o erro antes de
qualquer teste em navegador. Não foi feita validação funcional via
Playwright simulando pressionar o controle de verdade (fora do escopo
dado o tempo -- esse tipo de teste de UI/gamepad não tem infraestrutura
automatizada hoje, mesma limitação já registrada pro resto do client-side
da Arena).

**2) Observabilidade -- logs sob demanda + captura de erro client-side**,
pra fechar o gap que impediu investigar o "jogo não carrega" de verdade:

- `app.js`: `window.onerror`/`unhandledrejection` agora reportam pro
  `arena-auth` (`POST /client-error`, novo endpoint), que loga
  estruturado (matchId/slot/role/contexto/mensagem) com throttle de 3s
  por matchId+slot (evita um loop de erro inundar o log).
- `arenaServer.service.ts`: `getArenaContainerLogs(ip, container, tail)`
  -- generaliza o padrão já usado em `captureArenaContainerLogs`, mas sob
  demanda (não só no desligamento) e devolvendo o texto em vez de só
  logar. `ARENA_LOG_CONTAINERS` é uma união literal (`cloud-game-local`,
  `arena-auth`, `arena-admin`) -- nunca string livre dentro do comando
  SSH, mesmo sendo rota só de SUPER_ADMIN.
- Rota nova `GET /api/arena/server/logs?container=&tail=` (mesma
  restrição de `/server/start`/`/server/stop`).
- `gamo-admin`: visualizador de logs na tela da Arena (escolhe container,
  busca últimas 500 linhas) -- só habilitado com a arena ligada.

**Não resolvido ainda** (precisa de uma VM rodando de verdade pra
validar): nenhuma das duas correções foi testada contra uma Arena ligada
de verdade nesta sessão, já que a VM do incidente anterior já tinha sido
destruída antes dessas mudanças começarem. Usuário pretende testar de
novo com os participantes -- a captura de erro client-side e o endpoint
de logs devem dar sinal de verdade na próxima vez que "o jogo não carrega"
acontecer (coisa que não existia até agora).

Validado: 2156 testes (2146 + 10 novos: 5 do controller `getServerLogs`,
5 do endpoint `/client-error` no `arena-auth`) passando, `tsc --noEmit` e
`eslint` limpos em `gamo-api`/`gamo-admin`. Commitado localmente em 3
commits (`79a5cc2` abstração de provedor, `b572001` remapeamento +
observabilidade backend, `ddcc2d8` visualizador de logs no admin) --
**nenhum push feito** (não solicitado).

## Causa raiz real do "jogo não carrega" -- confirmada ao vivo (2026-10-01)

Usuário religou a Arena e começou a testar com os participantes que
tinham reportado problema no torneio anterior. Uma pessoa entrou pelo
celular e reproduziu o sintoma na hora: emulador carrega (interface,
botões, D-pad), mas o vídeo do jogo nunca aparece.

**Investigação** (autorizado pelo usuário a usar SSH de produção pra
isso, revertendo o bloqueio do classificador de segurança registrado
antes -- dessa vez com confirmação humana direta e específica):

- `docker logs arena-auth`: handoff/autenticação funcionou perfeitamente
  -- token validado, sala certa, `roomId`/`av` corretos chegando no
  jogador via polling de `/verify`. Esse lado nunca foi o problema.
- `docker logs cloud-game-local` (o log que importava): a negociação
  WebRTC aconteceu inteira -- oferta/resposta trocadas, candidatos ICE
  (host, srflx via STUN) trocados dos dois lados -- mas terminou assim,
  ~30s depois:
  ```
  rtc [ice] connection state change state=failed
  WebRTC connection fail! connection: connecting, ice: failed, gathering: complete, signalling: stable
  ```
- Causa raiz: `pkg/config/config.yaml` (nosso próprio override) só tinha
  **STUN** configurado (`stun.l.google.com`), nenhum **TURN**. STUN
  sozinho não resolve quando um dos lados está atrás de NAT restritivo/
  CGNAT -- extremamente comum em internet de operadora móvel no Brasil.
  Sem TURN (retransmissor), a conexão P2P direta simplesmente falha
  nesse cenário -- bate 100% com o sintoma relatado (funciona pra
  maioria, falha sempre pras mesmas pessoas, independe de navegador,
  acontece até no celular).

**Corrigido**: servidor TURN (coturn) auto-hospedado na própria VM --
ver commit `ff4dc2a`. Considerei e descartei um TURN de terceiro
gratuito (Metered.ca/Open Relay) -- o plano grátis deles (20GB/mês) daria
umas 14h de jogo retransmitido por mês **no total**, insuficiente pro
caso de uso (vídeo contínuo a ~3.2 Mbit/s por sessão). Self-hosted não
tem esse limite e não depende de outro fornecedor.

Detalhes técnicos:
- `docker-compose.yml`: novo serviço `coturn` (imagem oficial
  `coturn/coturn:4.6`), `network_mode: host` (recomendado pelo próprio
  projeto coturn pra Docker -- TURN precisa anunciar portas reais, não
  combina com NAT de porta do Docker).
- `config.yaml`: nova entrada em `iceServers` com `urls`/`username`/
  `credential` (confirmei os nomes exatos de campo direto no código-fonte
  do cloud-game no GitHub, `pkg/config/webrtc.go` -- struct `IceServer`).
- IP da VM, usuário e senha são **placeholders** nos arquivos
  versionados (`__TURN_EXTERNAL_IP__`, `__TURN_USERNAME__`,
  `__TURN_PASSWORD__`) -- substituídos por `sed` durante o
  provisionamento (`runProvisioning`, logo depois de copiar os
  overrides), mesmo padrão já usado pelos outros patches de arquivo
  estático deste projeto. Não dá pra fixar o IP no arquivo porque a VM é
  recriada do zero a cada "Ligar Arena".
- Credenciais novas: `ARENA_TURN_USERNAME`/`ARENA_TURN_PASSWORD` (env
  vars no Railway, geradas em **hex puro** de propósito -- `sed` quebra
  com alguns caracteres especiais, ex. `/`, que apareceriam numa senha
  base64 comum).
- Firewall: abri `3478/tcp+udp` (controle TURN/STUN) e `49152-49252/udp`
  (faixa de retransmissão -- uma porta por conexão relayed; 100 portas
  dá folga de sobra pro tamanho de torneio que a Gamo roda hoje) no
  passo `opening_firewall` já existente.
- `startArenaServer()` ganhou a mesma checagem de pré-requisito que já
  existia pro `CLOUDFLARE_API_TOKEN` -- falha rápido e claro
  (`ARENA_NOT_CONFIGURED`) se as credenciais TURN não estiverem
  configuradas, em vez de deixar os placeholders vazarem pro arquivo
  final silenciosamente.

**Não testado ainda contra uma conexão real travada** (a mudança foi
commitada e pushada, redeploy disparado, mas a validação de "será que
resolve de verdade pra quem tinha o problema" depende do próximo teste
ao vivo do usuário com os mesmos participantes). Validado até aqui: `tsc
--noEmit` limpo, suíte de testes do módulo arena passando (94 testes),
nomes de campo do YAML confirmados contra o código-fonte real do
cloud-game (não foi chute).

## D-pad "vazando" pelo analógico -- controle iPega PG9076 (2026-10-02)

Usuário reportou outro problema relatado por um jogador, dessa vez com
mais detalhe: controle iPega PG9076 (Bluetooth e USB), precisou de
calibração manual, o D-pad foi reconhecido certinho na TELA de
mapeamento, mas **dentro do jogo só o analógico move o personagem -- o
D-pad não faz nada**. Usuário mencionou que outra pessoa já tinha
relatado algo parecido antes.

**Causa raiz** (achada só por leitura de código, sem o hardware físico em
mãos -- risco assumido e comunicado ao usuário antes de implementar):
`checkJoystickState()` em `joystick.js` tem um bloco **incondicional** que
sempre lê os eixos 0/1 do gamepad (o analógico esquerdo, pelo padrão
W3C) e trata isso como um "segundo D-pad" -- independente de existir
calibração manual ativa ou não. Pro iPega (e aparentemente outros
controles genéricos Bluetooth), o D-pad físico é reportado via EIXO (não
botão) -- então a calibração manual salva o D-pad corretamente como um
binding de eixo (`customAxisBindings`), mas esse binding **competia**,
tick a tick (a cada 10ms), com o bloco incondicional do analógico pela
MESMA tecla (ex.: "cima") -- um dizia "solto" (baseado no analógico
parado), o outro dizia "pressionado" (baseado no D-pad real), gerando um
"pisca-pisca" rápido demais pro jogo reconhecer como movimento sólido.
Esse mesmo mecanismo também explica o bug antigo "só as setinhas
funcionam" em controle não-reconhecido (documentado antes, só recebeu um
aviso reativo, nunca uma correção de verdade).

**Usuário levantou preocupação legítima**: mexer nessa área de novo
(já teve um bug real de implementação nela mais cedo hoje) sem quebrar o
que já funciona pros outros controles. Decisão tomada em conjunto:
correção **granular por direção**, não um interruptor único pro
controle inteiro -- evita o cenário de alguém calibrar um controle
"standard" (ou qualquer outro) e pular especificamente os passos de
D-pad no assistente ("não preciso, já funciona"), o que com um
interruptor único deixaria essa pessoa sem direção nenhuma.

**Implementação** (`joystick.js`): novo `customBoundKeys` (um `Set` com
quais das 4 direções têm calibração manual ativa agora), populado em
`applyCustomBindings` (a partir das chaves do mapa salvo) e resetado nos
dois outros ramos de `activateGamepadMapping` (vazio pra "standard" sem
calibração -- comportamento de sempre preservado; com as 4 direções
marcadas pra controle não-reconhecido sem calibração -- fecha de vez o
vazamento antigo). Em `checkJoystickState`, cada uma das 4 chamadas
`checkJoystickAxisState(KEY.*, ...)` do bloco do analógico agora só roda
se aquela direção específica NÃO estiver em `customBoundKeys`.

Revisão manual dos 4 cenários possíveis antes de considerar pronto:
1. Standard sem calibração (maioria dos usuários) -- `customBoundKeys`
   vazio, zero mudança de comportamento.
2. Standard com calibração (feature nova de hoje) -- só a direção
   realmente calibrada deixa de competir com o analógico; direção pulada
   no assistente continua caindo no fallback, sem regressão.
3. Não-padrão com calibração salva (quem já usa hoje) -- mesma garantia
   que o item 2; corrige o caso do iPega sem arriscar quem já funciona.
4. Não-padrão sem calibração (inerte) -- D-pad também fica inerte de
   verdade agora, fechando o vazamento antigo.

Validado: `node --check` (sintaxe) limpo. **Não validado contra hardware
real** -- pedido explícito ao usuário de testar com duas pessoas depois
do deploy: quem reportou o iPega (confirmar o fix) e alguém com um
controle já funcionando hoje (confirmar que nada quebrou). Resultado
desses testes ainda pendente no momento deste registro.

## LetsCloud: plano B implementado com conta real (2026-10-02)

Diferente da tentativa com a Linode (abandonada por falta de trial
utilizável -- ver seção acima), dessa vez o usuário conseguiu um token de
API de uma conta real da LetsCloud, com crédito de verdade (R$70,00).
Testei tudo ao vivo contra a API deles ANTES de escrever o provider --
mesma disciplina que faltou da primeira vez com a Linode.

**Confirmado ao vivo** (`core.letscloud.io/api`):
- `GET /locations`: `SAO1` e `SAO2` (São Paulo) disponíveis.
- `GET /locations/SAO1/plans`: `2vcpu-4gb-80ssd` (R$100/mês) -- equivalente
  ao plano usado na Vultr.
- `GET /locations/SAO1/images`: `ubuntu-26.04-x86_64` disponível (mesma
  versão já usada nos outros provedores).
- **Achado real, não documentado em lugar nenhum**: a plataforma deles
  (Virtualizor, confirmado pelo campo `virtualizor_user_id` no `/profile`)
  **só aceita chave SSH formato RSA** -- a chave ed25519 que já usávamos
  pra Vultr foi rejeitada com `"Invalid key provided"`. Confirmei gerando
  uma chave RSA descartável e registrando com sucesso antes de gerar a de
  produção.
- **Dois outros achados só descobertos testando, não documentados**:
  (1) `POST /instances` sem o header `Accept: application/json` devolve
  um **redirect 302 pra uma página HTML** em vez de erro JSON -- típico de
  app Laravel que não reconhece a requisição como "espera JSON" (as rotas
  GET funcionavam sem esse header; só a criação de instância precisou
  dele). (2) Criar instância exige campo `password` (root) mesmo usando
  SSH key -- regras de senha são 12-32 caracteres, maiúscula+minúscula+
  dígito+especial; o caractere `_` está listado como aceito na mensagem
  de erro deles mas é **rejeitado na prática** (bug do lado deles,
  confirmado testando) -- usei `!` em vez disso.
- `GET /instances/{id}` não tem um campo "status" único -- só 3 booleanos
  (`built`/`booted`/`locked`), confirmados direto no código-fonte do SDK
  oficial (`letscloud-node`, GitHub) já que a doc pública
  (`developers.letscloud.io`) é uma SPA sem conteúdo legível via fetch.

**Refactor necessário**: `sshConnect()` (e as 4 chamadas dele em
`arenaServer.service.ts`) passou a receber a chave privada como
**parâmetro** em vez de ler um único env var fixo -- cada provedor agora
expõe sua própria chave via `CloudProvider.getSshPrivateKey()`. Motivo
direto: Vultr usa ed25519 (`ARENA_SSH_PRIVATE_KEY`), LetsCloud exige RSA
(`ARENA_LETSCLOUD_SSH_PRIVATE_KEY`, chave nova dedicada, registrada do
lado deles com slug `gamo-arena`). `startArenaServer()` ganhou uma
checagem genérica (não hardcoded pra um provedor só) que falha cedo se a
chave do provedor ATIVO não estiver configurada.

**Bloqueado agora**: conta nova da LetsCloud tem um limite de criação de
instâncias ("Voce atingiu o limite para criar novas instancias. Entre em
contato conosco.") -- usuário já pediu pro contato de lá aumentar,
aguardando resposta. Até isso ser liberado, não dá pra validar o
provisionamento completo de ponta a ponta (só API de consulta/SSH key foi
testada com sucesso).

Credenciais gravadas em produção (Railway): `LETSCLOUD_API_TOKEN` e
`ARENA_LETSCLOUD_SSH_PRIVATE_KEY`. Provedor ativo continua `vultr` por
padrão -- nada muda no comportamento de produção até um SUPER_ADMIN trocar
explicitamente pela tela do admin.

Validado: `tsc --noEmit` e `eslint` limpos, suíte do módulo arena com 108
testes passando (adicionou testes de `letscloudProvider` -- findByLabel/
create/destroy/getSshPrivateKey, incluindo a verificação de que a senha
gerada satisfaz as regras de complexidade deles -- e cobertura do novo
`getSshPrivateKey` na Vultr também).

### Validação de ponta a ponta de verdade + 3 bugs reais corrigidos (mesmo dia)

Contato do usuário na LetsCloud liberou o limite de criação de instâncias
logo depois do registro acima. Testei o ciclo completo (criar → consultar
por label → consultar por id → SSH → destruir) com instâncias reais --
e a implementação inicial, baseada só na doc/SDK oficial deles, tinha
**3 bugs reais** que só apareceram testando contra a API de verdade:

1. **Cota zero em SAO1**: a primeira tentativa de criar uma instância
   (`location_slug: "SAO1"`) travou com `"Voce atingiu o limite para criar
   novas instancias"`. O painel deles ("Location limits") mostrava DUAS
   linhas "São Paulo" -- uma zerada (0 instâncias/cores/RAM permitidos) e
   outra com cota real (3 instâncias, 6 vCPUs, 16GB). A API de
   `/locations` não expõe cota nenhuma, as duas apareciam como
   `available: true` igualmente -- só descobri testando criação de
   verdade. **Corrigido**: trocado pra `SAO2`, testado com sucesso.
   Contato do usuário confirmou que era mesmo um bug do lado deles e já
   corrigiu -- SAO1 deve voltar a funcionar, mas não há motivo pra trocar
   de volta agora que SAO2 já está validado.
2. **`POST /instances` não devolve dado nenhum da instância** -- só
   `{success, message}`. A doc/SDK oficial (`letscloud-node`) sugeria um
   objeto com `identifier`, mas a API real não manda isso. Pior: logo
   depois de criar, um `GET /instances` mostra a instância com
   **`identifier: null`** por ~10-20s, até a alocação terminar de
   verdade. **Corrigido**: `create()` agora faz o POST (ignora a
   resposta) e faz polling em `findByLabel` (a cada 3s, até 20 tentativas
   -- ~60s) até a instância aparecer com um identifier de verdade;
   `findByLabel` ignora entradas com `identifier: null` (trata como
   "ainda não existe").
3. **`ip_addresses` é um array de OBJETOS** (`[{address: "1.2.3.4"}]`),
   não de strings -- `normalize()` pegava o objeto inteiro em vez do IP.
   **Corrigido**, confirmado via `GET /instances/{id}` real.

**Validado end-to-end com sucesso**: criar instância (plano de produção,
`2vcpu-4gb-80ssd`) → descobrir id → SSH root com a chave RSA registrada
(`gamo-arena`) → `uname -a` respondeu → destruir. Único ajuste necessário
no fluxo de uso: a chave SSH só fica de fato disponível (`authorized_keys`
escrito pelo cloud-init) depois que os host keys do SSH são regenerados
no primeiro boot -- a MESMA margem de tempo que o loop de
`waiting_for_ssh` em `runProvisioning()` já tolera (24 tentativas, ~6min),
não precisou de ajuste nenhum nesse orçamento.

Instâncias de teste (3 no total, planos pequenos/baratos) criadas e
destruídas durante essa validação -- custo total desprezível.

Testes atualizados pra refletir os formatos reais (ip_addresses como
objetos, identifier:null, polling em vez de resposta direta do POST) --
suíte final: 111 testes no módulo arena, todos passando.

### 4º bug real + correção de texto (mesmo dia, depois do usuário ligar a Arena de verdade)

Usuário ligou a Arena com LetsCloud selecionada no admin -- funcionou --
e reportou dois problemas pequenos:

**Texto hardcoded "Vultr"** no diálogo de confirmação do admin
(`gamo-admin/src/pages/arena/create.tsx`), mesmo com LetsCloud ativa. Só
cosmético -- trocado por texto genérico ("no provedor de nuvem
configurado"), sem precisar passar o nome do provedor pela árvore de
componentes.

**4º bug real da LetsCloud**: a instância de teste `gamo-test-diag3`
(da validação de `getById` logo acima) **não tinha sido destruída de
verdade**, apesar do `DELETE` ter respondido `{"success":true,"message":
"Instance successfully deleted"}` na hora. Só apareceu porque o usuário
visualizou o painel deles e viu as duas instâncias "LIGADA". Testei de
novo manualmente e o segundo `DELETE` (minutos depois) funcionou de
verdade -- hipótese mais provável: a API aceita (e responde "sucesso")
um `DELETE` numa instância ainda `locked: true` (true por ~1-2min logo
após criar) sem de fato destruir nada.

Essa é a MESMA categoria de risco do incidente real da Vultr (2026-09-30,
VM órfã cobrando sem ninguém perceber -- ver seção acima). **Corrigido**:
`destroy()` agora confirma via `getById` (3s de espera, até 5 tentativas)
que a instância realmente sumiu depois do `DELETE`, re-tentando se ela
ainda existir, e só desiste com um erro claro depois de 5 tentativas --
`stopArenaServer()` nunca mais vai reportar sucesso silencioso numa
instância que continua rodando/cobrando.

Validado: `GET /instances/{id}` numa instância já destruída de verdade
responde HTTP 200 com `{"success":false,"message":"Instance not
found"}` (confirmado ao vivo) -- `getById`/`normalize` já tratavam isso
corretamente (retornam `null`), não precisou de ajuste nesse ponto.
Testes novos cobrindo o retry (sumiu de primeira / só na 2ª tentativa /
nunca sumiu -> erro claro) -- suíte final: 113 testes no módulo arena.

## Player 2 do SNES só funcionava pelo controle P4 (2026-10-11)

Sintoma: em Super Mario Kart (3 ROMs diferentes testadas), o controle do
player 2 não fazia nada; o que mexia o 2º kart era o controle **P4**.

Causa: o `config.yaml` do CloudRetro liga o **Super Multitap** (adaptador de
4 controles) na porta 2 do SNES em toda partida (`hid: {1: 257}`, padrão do
projeto upstream). No snes9x, com o multitap na porta 2, os controles do
adaptador viram os jogadores 2-5 (`port * offset + j`, conferido no
`libretro.cpp`). Jogo de 2 jogadores que não conhece o multitap lê a porta 2
como controle comum, mas com o bit de seleção do adaptador numa posição em
que ele entrega o 3º controle dele -- o player 4. Depende do jogo (alguns
funcionavam por acaso); só SNES tem essa regra no config.

Correção: multitap só em partida de **3+ jogadores**.
- `overrides/pkg/config/config.yaml`: o bloco `hid` do SNES fica entre
  `# GAMO_SNES_MULTITAP_BEGIN` e `# GAMO_SNES_MULTITAP_END` (não mudar o texto).
- Provisionamento: guarda a versão completa em `/opt/arena/config.base.yaml`.
- gamo-api (`uploadRomsToArenaVm`, `shouldUseSnesMultitap`): manda
  `snesMultitap=true|false` no `create-match` (chaveamento usa os
  participantes reais).
- admin-server (`snesMultitap.js`): entre o `compose rm` e o `compose up`,
  regera o `config.yaml` a partir do base, com ou sem o bloco. VM antiga
  (sem `config.base.yaml`) ou campo ausente = não mexe em nada.

Só vale a partir do próximo "Ligar" da Arena (o admin-server e o config vão
pra VM no provisionamento).

**Atualização (mesmo dia): a 1ª versão não funcionou.** O admin-server
removia o bloco do multitap do `config.yaml` corretamente, mas o log do
worker continuava com `snes:{... Hid:map[1:[257]] ...}`. O CloudRetro
carrega o config embutido (que liga o multitap) e aplica o `./config.yaml`
por cima: chave ausente volta do embutido. Correção: com 1-2 jogadores o
bloco entre os marcadores vira `hid: {1: 1}` (RETRO_DEVICE_JOYPAD, controle
comum na porta 2), sobrescrevendo o valor embutido. Para conferir numa
partida: o log `conf:` do `cloud-game-local` deve mostrar `Hid:map[1:[1]]`
no `snes`.

## Salas simultâneas (2026-10-21)

Pedido depois do campeonato: várias partidas ao mesmo tempo, número de salas controlado pelo
admin (começando em 4), jogador vendo "X salas · Y em uso · Z livres", admin vendo/fechando
salas, e resolver os dois pontos fracos achados: desligar a VM não liberava a sala e partida de
torneio sobrescrevia a sessão que estivesse rodando (reiniciava a Arena inteira).

Desenho escolhido: **pilhas independentes** (1 container CloudRetro + 1 xvfb por sala, cada
uma com coordinator e worker próprios), em vez de depender do roteamento multi-worker do
CloudRetro. Detalhes de portas, reserva, inatividade e rotas no `gamo-api/AGENTS.md`, seção
"Arena: salas simultâneas". Decisões do usuário: teste na VM de produção com 4 salas fora do
horário de uso; inatividade = 10 min + aviso de 2 min; VM continua 2 vCPU/4 GB (limite é o
número de salas no admin).

## Rotina automática (2026-10-25)

O admin agenda a Arena para ligar e desligar sozinha (ex.: todo dia 19:30–23:30). Dentro da
janela não há desligamento por 2h de inatividade. Custo = tamanho da janela (4h x 30 dias ≈
120h/mês). Regras e rotas no `gamo-api/AGENTS.md`, seção "Arena: rotina automática".
