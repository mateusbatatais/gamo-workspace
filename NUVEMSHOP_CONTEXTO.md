# Contexto: integração de estoque Gamo ↔ lojas externas (Nuvemshop)

> Arquivo temporário de passagem de contexto entre chats. **Apagar quando a integração estiver
> finalizada.** Não está no git (raiz do workspace). Atualizado em 2026-11-04.

## Objetivo
Lojistas que vendem no Gamo e numa loja própria (começando pela Nuvemshop) mantêm o estoque
igual nos dois lados: vendeu na loja → baixa no Gamo; vendeu no Gamo → baixa na loja. Vale para
qualquer lojista. Sincroniza SÓ estoque/status (não preço, fotos, descrição). Recurso gratuito.
Também permite **importar o catálogo da loja** para o Gamo (Fase 3).

## Onde está
- Repos em `D:\_p\Gamo\gamo-workspace\` (gamo-api = Express + Prisma + Postgres; gamo-web =
  Next.js; gamo-admin = Vite). Push no branch principal = deploy (api `master` com migration,
  web `main`; admin `master` vai pelo Cloudflare).
- **Fonte da verdade:** `gamo-api/docs/STORE_INTEGRATION_ROADMAP.md` (decisões, fases,
  checklists, pendências). Resumo técnico em `gamo-api/AGENTS.md` › "Integração com lojas
  externas". Leia os dois antes de mexer.

## Decisões tomadas (não reabrir)
1. Vínculo item do Gamo ↔ variante da loja pelo **SKU** (só jogo, console, acessório; kits fora).
2. Ao vincular, **a loja é a fonte da verdade**: o item do Gamo recebe o estoque da loja.
3. Venda no Gamo avisa a loja **já na reserva do checkout** (StockReservation).
4. **Venda dupla**: não fica negativo, status CONFLICT, notificação `STORE_DOUBLE_SALE`; o
   lojista decide. Nada é cancelado automaticamente.
5. Conexão por OAuth onde existir; senão o lojista cola a chave.
6. Arquitetura genérica: núcleo + um adaptador por plataforma.
7. (2026-11-04) **Só item à venda (SELLING) pode ser vinculado** — vincular item da coleção o
   punha à venda sozinho, sem revisar preço/condição. O seletor lista só itens à venda.
8. (2026-11-04) Importação da loja: itens entram **à venda**; condição **sempre em branco**
   para o lojista revisar.

## Histórico de commits (tudo em produção)
| Fase | gamo-api | gamo-web | gamo-admin |
|---|---|---|---|
| 0 — SKU nos itens | `0e98a970` | | |
| 1 — núcleo | `4e86763d` | | |
| 2 — Nuvemshop + assistente de vínculo | `d8010871` | `64b2c0d2` | |
| Só item à venda pode ser vinculado | `21da174e` | `f597d381` | |
| 3 — importar catálogo da loja | `b85d13fd` (migration `20261104180000_store_import_variant_ref`) | `c61e1f51` | `f9afc2a` |

## Configuração em produção (feita em 2026-11-04)
- **App no Nuvemshop Partners**: "Gamo", App ID **50344**, distribuição "Loja de aplicativos",
  status "Em desenvolvimento" (não publicado). E-mail/User-Agent: `contato@gamo.games` (igual ao
  `USER_AGENT` em `gamo-api/src/infra/stores/nuvemshop.ts`).
  - Permissões: Products (read/write) e Orders (read). Nada de Scripts/Customers.
  - Redirecionamento: `https://api.gamo.games/api/store-integrations/nuvemshop/callback`
  - LGPD: `.../webhook/nuvemshop/store-redact`, `.../customers-redact`,
    `.../customers-data-request` (base `https://api.gamo.games/api/store-integrations`).
  - Pendente no portal: "Dados de publicação" (incluir URL da política de privacidade do Gamo)
    e "Solicitar homologação" — só depois de validar na loja real.
- **VPS**: `NUVEMSHOP_APP_ID` e `NUVEMSHOP_CLIENT_SECRET` adicionados ao `/opt/gamo/api.env`
  (backup em `/opt/gamo/api.env.bak-20261104`), container `api` recriado. Não imprimir o
  conteúdo do `api.env`.
  - Acesso SSH a partir deste PC: `ssh -i ~/.ssh/id_ed25519 deploy@179.198.100.200` (chave
    adicionada ao `authorized_keys` do `deploy` em 2026-11-04; a `gamo_staging_rsa` citada no
    AGENTS.md raiz não existe neste PC).
  - Opcionais ainda não definidas: `STORE_WEBHOOK_BASE_URL` (padrão `https://api.gamo.games`),
    `NUVEMSHOP_STOCK_TAKEN_EVENT` (padrão `order/created`; usar `order/paid` se a Nuvemshop só
    tirar o estoque no pagamento).
  - `secret.txt` na raiz do workspace (ignorado pelo git) tem o client secret — pode ser apagado.
- **Loja demo**: "Gamo demo" (#8468620, `gamodemo.lojavirtualnuvem.com.br`). Fica "em reforma"
  para o público (aba anônima não abre). Conectada ao Gamo (StoreConnection NUVEMSHOP ACTIVE desde
  2026-11-04 18:51). Produto "Console Nintendo Switch 2 Edição Zelda", SKU `123321`, estoque 5,
  **vinculado** ao UserConsole #5854 (quantidade 5, SELLING) — vínculo id 1.

## Arquitetura (gamo-api, `src/modules/storeIntegration/`)
- `storeProvider.ts` — contrato `StoreProviderAdapter` (listCatalog, getVariants, adjustStock,
  parseWebhook, fetchOrderLines?, refreshCredentials?) + registro (`providers.ts`).
  `ExternalVariant` tem `categories?: string[]` (Fase 3).
- `storeStock.ts` — saída Gamo → loja (worker; disponível = quantity − reservas se SELLING,
  senão 0; envia só o delta contra `syncedStock`).
- `storeOrders.ts` — entrada loja → Gamo (STOCK_TAKEN/RETURNED, idempotente por `StoreOrderEvent`).
- `storeReconcile.ts` — cron 30 min, divergência só aplicada se repetir após 20 min.
- `storeConnection.ts` — credenciais criptografadas, saúde da conexão.
- `storeIntegration.service.ts` — conexões, `linkItemToStore` (recusa item != SELLING), webhook.
- `storeLinks.service.ts` — assistente de vínculo (catálogo, itens à venda, lote, auto por SKU);
  exporta `getOwnedConnection` e `linkItems`.
- `storeNuvemshop.service.ts` — OAuth. Adaptador: `src/infra/stores/nuvemshop.ts`
  (`PRODUCT_FIELDS` inclui `categories`).
- Saída por **gatilho no Postgres** (migration `20261029120000_store_integration`): mudar
  quantity/status, apagar item ou criar/apagar StockReservation enfileira o vínculo. Código novo
  que mexe em estoque não precisa chamar nada.

### Fase 3 — importar catálogo (novo em 2026-11-04)
- `storeImportScan.ts`:
  - `startStoreImportScan` → WorkerTask `store-import-scan` (import-worker, `maxAttempts: 1`,
    dedupe por conexão; leitura da mesma loja nos últimos 30 min é reaproveitada).
  - `runStoreImportScan` lê até 25 páginas / 5.000 produtos; deixa de fora: vinculado,
    `skuInGamo` (SKU num item à venda → usar "Vincular tudo por SKU"), `skuNotForSale` (SKU num
    item fora de venda → pôr à venda e vincular), sem controle de estoque, sem estoque.
    Resultado fica em `WorkerTask.result`.
  - `startStoreImportSessions` aplica os tipos corrigidos pelo lojista, confere importação em
    aberto de TODOS os tipos envolvidos antes de criar, cria 1 sessão por tipo via
    `createSessionFromStoreRows` (status SELLING, price, quantity = estoque, sku,
    `storeVariantRef`) e **apaga a WorkerTask** (reaproveitar duplicaria produtos sem SKU).
- `storeImportClassify.ts` — regras puras (palavras do nome, categoria da loja, plataforma pelo
  registro + `EXTRA_PLATFORM_ALIASES`, limpeza do título) + prompt/parse da IA.
  IA: `runStoreImportClassifyPrompt` em `integration/ai/ai.service.ts`, `AiFeature`
  `store-import-classify`, **sem busca no Google**, lotes de 50, **máx. 10 lotes por leitura**
  (`MAX_AI_BATCHES`). Vai para a IA: sem tipo, ou jogo sem plataforma. IA fora/teto atingido →
  o lojista escolhe. Estimativa ~R$ 0,06/lote (preço promocional até 2026-12-31; dobra em 2027).
- `storeImportLink.ts` — `storeVariantRef` = `"conexão:produto:variante"`; os 3 importadores
  gravam a coluna e, no `executeImport`, chamam `enqueueStoreImportLinks` com os itens criados;
  WorkerTask `store-import-link` (`runStoreImportLink`) lê o estoque atual na loja e vincula via
  `linkItems`. Handlers registrados em `src/workerTaskHandlers.ts`.
- Importadores (`userGamesImport`, `userConsolesImport`, `userAccessoriesImport`): novo método
  público `createSessionFromStoreRows`; consoles/acessórios ganharam `buildSessionFromRows`
  (antes embutido no `uploadFile`). Repository de jogos mapeia campo a campo — campo novo precisa
  entrar lá (tem teste).
- Rotas novas em `/api/store-integrations`: `POST /:id/import/scan`,
  `GET /:id/import/scan/:taskId`, `POST /:id/import/scan/:taskId/start` (body `{ types }`).
- Admin: rótulo "Importação da loja: classificação" no card de uso de IA.

### Rotas existentes (`/api/store-integrations`)
`POST /webhook/:provider[/:topic]` (corpo bruto), `POST /nuvemshop/connect`,
`GET /nuvemshop/callback`, `GET /`, `DELETE /:id`, `GET /:id/catalog?cursor=`,
`GET /:id/items?search=&type=`, `POST /:id/links`, `POST /:id/links/auto`, `DELETE /links/:linkId`.

## gamo-web
- `/account/integrations` → seção "Lojas virtuais" (`NuvemshopIntegrationCard`). Testada no
  navegador em 2026-11-04: conectar e vincular funcionaram.
- `/account/integrations/stores/[id]` → `StoreLinkWizard` (catálogo, sugestão por SKU, seletor de
  item à venda, vincular tudo por SKU, card "Importar produtos da loja").
- `/account/integrations/stores/[id]/import` → `StoreImportWizard` (ler loja, `?task=` na URL,
  filtros por tipo, trocar tipo, importar, botões para as revisões
  `/user/collection/{games,consoles,accessories}/import` — lá aparece "Continuar de onde parou").
  **Nunca aberta no navegador.**
- Hooks: `hooks/integrations/useStoreIntegrations.ts`. Textos: `account.integrations.stores`
  em `messages/pt.json` e `en.json`.

## Testes
- api: `storeIntegration/__tests__/*` (inclui `storeImportScan.test.ts`,
  `storeImportClassify.test.ts`), `src/infra/__tests__/nuvemshop.test.ts`, testes de
  `storeVariantRef`/enqueue nos 3 `*Import.service.test.ts` e
  `userGamesImport.repository.test.ts`. Suíte inteira: 5.229 passando.
- web: `StoreImportWizard.test.tsx`. Suíte inteira: 1.781 passando.
- Gap conhecido: sem Playwright para `/account/integrations` (ver `gamo-web/TESTING_GAPS.md`).

## O que falta
### Validar (o dono vai testar numa loja real, em outro perfil)
- [ ] Teste 1, venda na loja → baixa no Gamo: pedido sem pagar; ver se a Nuvemshop baixa o estoque
      na criação ou só no pagamento (se no pagamento, `NUVEMSHOP_STOCK_TAKEN_EVENT=order/paid`);
      marcar pago; cancelar → volta.
- [ ] Teste 2, venda no Gamo → baixa na loja: outra conta no Gamo vai até o pagamento sem pagar →
      loja deve cair em até 1 min (reserva); abandonar → volta.
- [ ] Teste 3: venda dupla.
- [ ] Assinatura HMAC dos webhooks; ajuste de estoque em loja com vários depósitos; desinstalar app.
- [ ] Importação da loja: abrir a tela pela 1ª vez, classificação com produtos reais, custo real
      da IA por lote (card "IA" do admin).
- Para acompanhar no banco: `docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d
  "$POSTGRES_DB"'` em `/opt/gamo` (tabelas `StoreConnection`, `ExternalListingLink`,
  `StoreStockSync`, `StoreOrderEvent`, `WorkerTask`). Comandos `docker compose exec` via SSH
  precisam de `</dev/null` (ou do SQL pelo stdin).

### Limitações conhecidas da importação
- Console e acessório: o cadastro exige condição; sem preencher na revisão, entram como **Usado**
  (padrão do `createUserConsole`/`createUserAccessory`). Jogo fica sem condição.
- Região segue o padrão da planilha (`US`) quando não informada.
- Bug antigo notado (não mexido): `userGamesImport.repository.createImportMatches` não repassa
  alguns campos da linha (ex.: `userChecked`, `userEditionType`, `userEditionName`). Vale conferir.

### Funcionalidades ainda não feitas
- Sugestão de vínculo por nome parecido (sem SKU) — trigram no Postgres, nunca tabela grande em memória.
- Indicador no anúncio de que o item está vinculado a uma loja.
- gamo-app: status da conexão e notificações `STORE_*` abrindo `/account/integrations` no site.
- Linha na página `/features` do gamo-web quando estiver validado (ver `gamo-web/AGENTS.md`).
- Portal Nuvemshop: dados de publicação + homologação.
- Fase 4: outras plataformas (Mercado Livre, Shopify, WooCommerce, Tray, Loja Integrada) — cada
  uma é um adaptador.

### Pendências técnicas conhecidas
- Falha de rede ambígua no ajuste de estoque pode ajustar 2x (a reconciliação detecta). Raro.
- Reserva de kit não tira estoque dos itens do kit na loja (só a venda tira).
- "Vincular tudo por SKU" e a leitura da importação leem no máximo 25 páginas por vez.

## Convenções (resumo; detalhes nos AGENTS.md)
- Controller → Service → DB; erros com AppError; sem `any`. Código/commits em inglês,
  comentários/docs em português. Respostas ao dono em português.
- Rotina agendada só via `scheduleCron`/`scheduleInterval`; trabalho pesado vai para WorkerTask
  (import-worker), nunca no processo da API.
- IA paga em massa: estimativa + ok do dono antes.
- gamo-web: chamadas à API só por hooks; textos via next-intl (pt e en juntos).
- Commitar ao terminar; **push/deploy só com ok do dono**. Pre-push roda testes/lint/build (o do
  web passa de 10 min). Outras sessões commitam em paralelo nos mesmos repos: adicionar ao commit
  só os próprios arquivos.
- Antes de concluir: `/test-coverage-review` (feature/bug) e `/lgpd-review` se tocar dado pessoal.
