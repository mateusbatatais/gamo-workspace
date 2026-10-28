---
name: test-coverage-review
description: Revisão de cobertura de testes da tarefa/diff atual no monorepo Gamo — bugfix sem teste de regressão, feature nova sem teste de golden-path, e cruzamento com o catálogo de gaps históricos (TESTING_GAPS.md). Use antes de finalizar qualquer tarefa que corrija um bug ou adicione/altere uma funcionalidade em gamo-web, gamo-app ou gamo-api. Não use para revisão geral de bugs/performance (isso é /code-review) nem para conformidade LGPD (isso é /lgpd-review).
---

# /test-coverage-review

Revisão de cobertura de testes para uma mudança em qualquer um dos 3 projetos com testes automatizados do monorepo Gamo (gamo-web, gamo-app, gamo-api).

## Quando isto se aplica

Rode isto antes de considerar concluída qualquer tarefa que:
- corrige um bug de comportamento (não é puro refactor/estilo/config);
- adiciona ou altera uma funcionalidade user-facing (tela, fluxo, endpoint com regra de negócio);
- toca um arquivo/módulo já listado como gap conhecido em `TESTING_GAPS.md` do repo correspondente.

Se a tarefa atual é puro refactor sem mudança de comportamento, atualização de dependência, documentação, ou config, não é necessário rodar este skill.

## Passos

1. **Delimitar o escopo**: identifique os arquivos tocados pela tarefa atual (diff em progresso, ou os arquivos que você está prestes a considerar como "prontos") e em qual(is) repo(s) eles estão.

2. **Delegar a análise** ao subagente `test-coverage-reviewer` (Agent tool, `subagent_type: "test-coverage-reviewer"`) quando o escopo for maior que uma mudança trivial — ele é somente-leitura e sabe cruzar o diff com o catálogo de gaps de cada repo (`TESTING_GAPS.md` + `.audit/`) e com os padrões de teste fraco/bug recorrente já documentados. Passe a ele: quais arquivos mudaram, em qual(is) repo(s), o que a tarefa pretende fazer, e se já existe algum teste incluído na própria tarefa. Peça achados no formato `[severidade] arquivo:linha — o que falta — cenário de regressão sem o teste — ação recomendada`.

3. **Reportar ao usuário**: resuma os achados por severidade. Bug corrigido sem nenhum teste de regressão, ou feature de alta prioridade (dinheiro/autenticação/dado pessoal) sem teste de golden-path, é bloqueante — não declare a tarefa concluída sem ao menos escrever o teste faltante ou mencionar explicitamente que ficou pendente e por quê. Gaps de baixa prioridade (UX/visual) podem virar item de acompanhamento em vez de bloquear, a critério do usuário.

4. **Fechar gap conhecido quando fizer sentido**: se o achado aponta que a área tocada já está listada em `TESTING_GAPS.md`, essa é a oportunidade de escrever o teste como parte da tarefa atual (não só de documentar de novo) — pergunte ao usuário se quer aproveitar, em vez de simplesmente adicionar mais uma linha ao backlog.

5. **Não duplique auditoria já feita**: se o achado já está documentado em `TESTING_GAPS.md` como gap conhecido e a tarefa atual não é sobre consertar aquilo especificamente, apenas cite que o gap é conhecido — não é preciso re-explicar o achado inteiro.
