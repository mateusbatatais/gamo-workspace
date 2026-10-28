# 🤖 AGENTS.md — Gamo Monorepo

> Este arquivo é o ponto de entrada para qualquer agente de IA trabalhando no monorepo Gamo.
> Leia **este arquivo primeiro**, depois acesse o AGENTS.md do sub-projeto relevante.

---

## Visão Geral da Plataforma

**Gamo** é uma plataforma de colecionismo de games (consoles, jogos e acessórios) que combina:
- Gerenciamento de coleção pessoal
- Marketplace peer-to-peer (com Stripe)
- Social/feed de colecionadores
- Leilões em tempo real
- Campeonato retrogame (inscrição, chaveamento automático e emulação em nuvem — módulos `tournament`/`arena` do `gamo-api`)

---

## Estrutura do Monorepo

| Diretório     | Stack                    | Função                              | AGENTS específico                        |
|---------------|--------------------------|-------------------------------------|------------------------------------------|
| `gamo-api/`   | Node.js + Express + Prisma | API REST + lógica de negócio       | [gamo-api/AGENTS.md](./gamo-api/AGENTS.md) |
| `gamo-web/`   | Next.js 16 + Tailwind    | Plataforma web principal            | [gamo-web/AGENTS.md](./gamo-web/AGENTS.md) |
| `gamo-app/`   | Expo / React Native      | App mobile (iOS e Android)          | [gamo-app/AGENTS.md](./gamo-app/AGENTS.md) |
| `gamo-admin/` | Vite + React             | Painel administrativo (backoffice)  | [gamo-admin/AGENTS.md](./gamo-admin/AGENTS.md) |
| `gamo-city/` | Vite + React + Phaser 4  | "Modo game": mundo 2D em pixel art (personagem + mapa) | [gamo-city/AGENTS.md](./gamo-city/AGENTS.md) |

**Raiz versionada à parte:** a pasta `gamo/` é o repo `gamo-workspace` (este `AGENTS.md`, `.claude/skills`, `.claude/agents`, `infra/`, `bootstrap.sh`). Os `gamo-*` são repos próprios, ignorados pelo `.gitignore` da raiz. Máquina nova: clonar o `gamo-workspace` e rodar `./bootstrap.sh` (Git Bash) para clonar os 5 projetos. Mudou este arquivo, uma skill ou um agent → commit na raiz.

---

## Regras Globais (válidas em TODOS os sub-projetos)

### ❌ Nunca faça
- Criar lógica duplicada que já existe em outro módulo
- Introduzir uma nova biblioteca sem verificar se já existe uma equivalente no `package.json`
- Adicionar campos ao banco sem criar uma migration Prisma
- Chamar a API sem passar pelo service layer no backend (nunca acesse `db` diretamente no controller)
- Hardcodar strings de texto visíveis ao usuário (use i18n quando disponível)
- **Usar o tipo `any`**. Sempre utilize ou crie interfaces/tipos apropriados.
- **Rodar trabalho pesado de CPU no processo da API** (carregar tabela grande na memória e varrer em JS, loop longo sem I/O, lote disparado por usuário sem fila/limite/cancelamento). A API é um processo só: uma planilha de mil jogos derrubou o site em 2026-10-22. Ver `gamo-api/AGENTS.md` › "Trabalho pesado no processo da API".
- **Pular os hooks do git** (`git commit --no-verify`, `HUSKY=0`). Cada commit precisa passar sozinho nos testes do pre-commit — commit quebrado consertado por um "fix" seguinte já foi para produção uma vez (gamo-city, 2026-10-17).

### ✅ Sempre faça
- Consulte o AGENTS.md do sub-projeto antes de escrever qualquer código
- Verifique componentes/utilitários existentes antes de criar novos
- Respeite o padrão de nomenclatura já estabelecido no diretório onde está trabalhando
- Mantenha consistência de idioma: código e variáveis em **inglês**, comentários e docs em **português**
- **Sempre responda e planeje em Português.**
- Utilize tipagem estrita em todos os projetos (Web, API e App).
- Se a tarefa cria/altera campo de dado pessoal, tela que exibe dado pessoal, integração com terceiro que recebe dado pessoal, ou rota que exporta dados em massa, rode `/lgpd-review` antes de considerar a tarefa concluída (ver `.claude/skills/lgpd-review/SKILL.md`).
- Se a tarefa mexe no `gamo-city` (código, mapas Tiled, geradores, arte, som), rode `/city-review` antes de considerar concluída (ver `gamo-city/AGENTS.md`, seção "Regras que evitam retrabalho"; agents `city-reviewer` e `city-docs-keeper`). No mínimo: `pnpm verify` no gamo-city, e nunca `pnpm deploy:vps` com alteração fora do git.
- Se a tarefa corrige um bug de comportamento ou adiciona/altera uma funcionalidade (gamo-web, gamo-app ou gamo-api), rode `/test-coverage-review` antes de considerar a tarefa concluída (ver `.claude/skills/test-coverage-review/SKILL.md`). Existe um catálogo completo de gaps de teste por repo em `TESTING_GAPS.md` (raiz de cada projeto) — consulte antes de assumir que uma área já está coberta.
- Se a tarefa entrega uma funcionalidade nova voltada ao usuário final (web ou app) que faça sentido o usuário descobrir — não é qualquer ajuste interno/admin/infra —, avalie se ela deve entrar na página `/features` do `gamo-web` (mapa completo de funcionalidades, linkado só a partir do último passo do onboarding, sem link em nenhum menu). Ver `gamo-web/AGENTS.md` (seção "Página `/features`") para o passo a passo de como atualizar.

---

## Convenções Cross-Project

### Tipos compartilhados
Os tipos de domínio principais (ex: `UserGame`, `Console`, `Accessory`) são inferidos do schema Prisma em `gamo-api/prisma/schema.prisma`. Não redefina esses tipos nos frontends — importe-os via serviço ou defina-os localmente espelhando o schema.

### Autenticação
- **Web**: JWT em `localStorage["gamo_token"]` + cookie `gamo_token` (NÃO HttpOnly — o gamo-city, no mesmo domínio, lê esse login) + contexto de sessão Next.js. **Admin**: JWT próprio do painel
- **App**: Firebase Auth token enviado no header `Authorization: Bearer <token>`
- **API**: Middlewares em `gamo-api/src/middleware/` — use o middleware correto por rota

### Comunicação com a API
- Toda chamada ao backend deve passar por um **Custom Hook** em `hooks/` (frontend) ou pelo **service layer** (backend)
- Nunca use `fetch` ou `axios` diretamente em componentes de UI
- No `gamo-web` especificamente: use `hooks/` — a pasta `services/` não é o padrão adotado

---

## Produção (VPS)

> Runbook completo (preparação, migração, rollback, pendências): [gamo-api/deploy/README.md](./gamo-api/deploy/README.md).
> Nunca imprima o conteúdo de arquivos `*.env` nem variáveis de ambiente do servidor.

**Onde:** VPS Hostinger KVM 2 (Campinas/SP), IP `179.198.100.200`, Ubuntu. Desde 2026-10-08 site + API + banco rodam aqui (o Railway antigo é só um repasse para `api.gamo.games` — não é produção).
- Acesso: `ssh -i ~/.ssh/gamo_staging_rsa deploy@179.198.100.200` (usuário `deploy`, dono de `/opt/gamo`; `root@` só para administração do SO). SSH só por chave.
- Tudo em **Docker Compose em `/opt/gamo`**: `caddy` (proxy/HTTPS), `web` (gamo-web), `api` (gamo-api), `world` (tempo real do Gamo City — mesma imagem da API, `node dist/src/world-server.js`, limitado a 1 CPU/768 MB), `import-worker` (importações em massa por planilha — mesma imagem, `node dist/src/import-worker.js`, 1 CPU/512 MB; com `IMPORT_MATCHING_PROCESS=worker` na API e nele, a API só cria a sessão e o worker processa), `postgres` (16, publicado só em `127.0.0.1:5432`), `dozzle` (logs, `127.0.0.1:8888`).

**Domínios (Cloudflare):**
| Domínio | Proxy CF | Atende |
|---|---|---|
| `www.gamo.games` | laranja (Origin Certificate) | Caddy: `/images/*` estático, `/city/*` = gamo-city estático, resto → Next (`web`) |
| `gamo.games` | laranja | redireciona para `www` |
| `api.gamo.games` | **cinza** (Let's Encrypt; uploads > 100 MB) | `/world-socket/*` → `world` (jogo); resto → `api` (inclui socket.io do chat e leilões) |
| `admin.gamo.games` | — | gamo-admin no **Cloudflare Workers** (não é a VPS; build vars no painel do CF) |

Worker `gamo-error-page` na rota `www.gamo.games/*` mostra página amigável em erro/reinício (fail open).

**Como cada projeto vai para produção:**
- **gamo-api**: push em `master` → GitHub Actions "Deploy VPS" (roda num **runner self-hosted na própria VPS**, não no GitHub) → build da imagem na VPS + `deploy/swap.sh` (sem queda). O container roda **`prisma migrate deploy` ao subir** → migration commitada vai para o banco de produção no push. Push em `master` = deploy. O mesmo workflow recria os containers `world` (jogadores reconectam sozinhos) e `import-worker` (importação em andamento continua das linhas que faltam) com a imagem nova.
- **`docker-compose.yml`** (versionado em `gamo-api/deploy/`) também NÃO é sincronizado pelo deploy: mudou → copiar para `/opt/gamo/` (backup antes) e `docker compose up -d <serviço>`.
- **gamo-web**: push em `main` → mesmo esquema (+ rsync de `public/images` para `/opt/gamo/static/images`).
- **gamo-city**: manual, `pnpm deploy:vps` no gamo-city (build com base `/city` → `/opt/gamo/static/city`, troca atômica).
- **gamo-admin**: Cloudflare Workers (deploy pelo CF).
- **gamo-app**: EAS (build/OTA), fora da VPS.
- Workflows só rodam com a variável de repositório `VPS_DEPLOY_ENABLED=true`. Para acompanhar sem `gh` (não instalado): API do GitHub com a credencial do Git Credential Manager, ou direto na VPS (`journalctl -u 'actions.runner.*'`, `~/actions-runner/{api,web}/_diag/`).
- **Runner self-hosted (desde 2026-10-28):** a cota grátis de minutos do Actions acabou, então `deploy-vps.yml` (api e web) e `game-sync.yml` (web) usam `runs-on: [self-hosted, gamo-vps]` — runners `gamo-vps-api`/`gamo-vps-web` em `/home/deploy/actions-runner/`, serviço systemd. O build usa o builder buildx `gamo-limited` (1,5 CPU, prioridade baixa, 5 GB) para não derrubar o site. **Não mova para o runner da VPS** job pesado (Playwright, imagem da Arena): ele roda na mesma máquina da produção. Runbook: `gamo-api/deploy/README.md` › "Runner self-hosted".
- **Sem Actions nenhum** (GitHub fora do ar): `bash gamo-api/deploy/manual-deploy.sh api|web` a partir do PC (build local + envio por SSH; o web exige `gamo-web/.env.deploy` com as `NEXT_PUBLIC_*`).

**Caddyfile** (`gamo-api/deploy/Caddyfile` versionado) **NÃO é sincronizado pelo deploy**. Para mudar:
1. Editar no repo e commitar.
2. `scp` para `/opt/gamo/Caddyfile.next`.
3. Validar dentro do container: `docker cp` para `/tmp` + `docker compose exec -T caddy caddy validate --config /tmp/Caddyfile.next --adapter caddyfile`.
4. Guardar backup (`cp Caddyfile Caddyfile.bak-<data>`) e trocar o conteúdo **mantendo o arquivo** (`cat Caddyfile.next > Caddyfile`, por causa do bind mount; `mv` quebraria). Atualizar a cópia `Caddyfile.prod`.
5. `docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile` (sem queda; config inválida mantém a anterior).

**Operação:**
- **Logs:** admin → Auditoria → aba "Logs da API" (SUPER_ADMIN), ou Dozzle por túnel (`ssh -L 8888:127.0.0.1:8888 ...`).
- **Banco:** `docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` (o usuário NÃO é `postgres`), ou DBeaver por túnel SSH. Não existe console SQL no admin (decisão LGPD).
- **Backup:** cron 04:00 (`/etc/cron.d/gamo-backup` → `/opt/gamo/backup.sh`) envia dump para o Cloudflare R2 (bucket `gamo-backups`).
- **Reinício automático** do SO às 03:00 só quando há atualização pendente (menor uso: 02h–05h).
- Scripts via `ssh ... 'bash -s' <<EOF` que usam `docker compose exec` precisam de `</dev/null`, senão o exec engole o resto do script.
- Qualquer cópia/instância de teste da API usa **`DISABLE_BACKGROUND_JOBS=true`** (senão manda e-mail/push/saque para usuários reais).
- Site bloqueia `curl` sem User-Agent de navegador (403 do middleware de bots): isso não é queda.

---

## Mapa de Funcionalidades por Projeto

- App mobile → [gamo-app/gamo_app_feature_map.md](./gamo-app/gamo_app_feature_map.md)
- Admin panel → [gamo-admin/gamo_admin_map.md](./gamo-admin/gamo_admin_map.md)
- Web platform → [gamo-web/gamo_functionality_map.md](./gamo-web/gamo_functionality_map.md)
