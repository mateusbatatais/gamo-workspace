---
name: city-review
description: Checklist do Gamo City antes de commitar ou publicar (pnpm deploy:vps) qualquer mudança no gamo-city — código, mapas Tiled, geradores, arte, som. Garante as "Regras que evitam retrabalho" do gamo-city/AGENTS.md (produção = git, mapa é dado, gerador não apaga Tiled, nada pesado por quadro, áudio com fade, safeLocalStorage, protocolo com o servidor do mundo, teste para domínio novo, docs no mesmo commit). Use também quando o usuário disser que outra ferramenta (Codex, Antigravity) mexeu no mundo.
---

# /city-review

Revisão do **gamo-city** antes de considerar uma tarefa pronta ou publicar.

## Passos

1. **Escopo.** `git -C gamo-city status --short` e `git -C gamo-city diff --stat` (e `--cached`). Mapa
   `.tmj` modificado que a tarefa não tocou = edição do usuário no Tiled em andamento: **não commitar,
   não descartar, não regenerar** — só avisar.

2. **Verificações automáticas** (no gamo-city):
   ```bash
   npx tsc -b && npx eslint src scripts && npx vitest run
   ```
   Os testes já barram: regra por nome de mapa (`noMapIdRules.test.ts`), gerador gravando `.tmj` fora da
   trava (`generators.test.ts`), som de interação inexistente e mapas inválidos (`maps.test.ts`).

3. **Revisão das regras** — para mudança maior que trivial, delegue ao agent `city-reviewer`
   (somente-leitura; `.claude/agents/city-reviewer.md`) passando os arquivos tocados e o objetivo da
   tarefa. Para mudança pequena, percorra você mesmo o checklist dele.

4. **Protocolo com o servidor.** Se a tarefa muda o que o cliente envia (join, activity, vehicle, move,
   toggle, pong, voice), confira `gamo-api/src/modules/world/world.schema.ts`/`world.gateway.ts`. Mudança
   no servidor = commit/push no gamo-api (push em `master` = deploy de produção; usar commit seletivo e
   checar `git log origin/master..HEAD` antes).

4b. **Missões.** Se mexeu em `worldQuests.json` ou `worldUnlocks.json`, siga a regra 15 do
   `gamo-city/AGENTS.md`: nada de renomear/remover id nem tirar/reordenar meta de missão no ar sem ok
   do usuário; catálogo igual ao da API; `docs/mapa-das-missoes.md` atualizado.

5. **Docs no mesmo commit.** `docs/funcionalidades.md` (histórico do que mudou), `docs/para-conferir.md`
   (como testar), `ROADMAP.md` (só o que vem: tire o item entregue), `AGENTS.md` (como funciona, comandos,
   propriedades do Tiled). Arte/som não exigem crédito. Entrega grande ou feita por outra ferramenta:
   rode o agent `city-docs-keeper` antes de atualizar o roadmap.

6. **Publicar** (só quando pedido): tudo commitado → `pnpm deploy:vps` (o script recusa se houver
   alteração fora do git; mapa do usuário em edição → publicar de um `git worktree` limpo). Vagas de
   veículo mudaram → passam a valer quando a sala esvaziar (ou reiniciar o container `world`).

7. **Relatório ao usuário:** o que foi verificado, achados por severidade e o que ficou pendente.
