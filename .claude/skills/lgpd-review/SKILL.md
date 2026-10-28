---
name: lgpd-review
description: Revisão de conformidade LGPD (Lei nº 13.709/2018) da tarefa/diff atual no monorepo Gamo — dado pessoal, consentimento, exclusão/portabilidade, terceiros e exposição em telas admin. Use antes de finalizar qualquer tarefa que crie/altere campo de dado pessoal, tela que exiba dado pessoal, integração com terceiro, fluxo de cadastro/consentimento, ou rota administrativa/exportação em massa. Não use para revisão geral de bugs/performance — para isso use /code-review ou /security-review.
---

# /lgpd-review

Revisão de conformidade LGPD para uma mudança em qualquer um dos 4 projetos do monorepo Gamo (gamo-api, gamo-web, gamo-app, gamo-admin).

## Quando isto se aplica

Rode isto antes de considerar concluída qualquer tarefa que:
- adiciona ou altera um campo que armazena dado pessoal (nome, e-mail, CPF, telefone, endereço, geolocalização, dado bancário/Pix, foto, mensagem);
- adiciona uma tela (web/app/admin) que exibe dado pessoal de um usuário para outro usuário ou para um admin;
- integra um serviço de terceiro que recebe dado pessoal (pagamento, IA, e-mail, frete, analytics, autenticação);
- mexe no fluxo de cadastro, login, consentimento, exclusão de conta ou exportação de dados;
- adiciona uma rota administrativa nova, especialmente uma que lê em massa ou exporta dados de usuários.

Se a tarefa atual não se encaixa em nenhum desses casos, não é necessário rodar este skill.

## Passos

1. **Delimitar o escopo**: identifique os arquivos tocados pela tarefa atual (diff em progresso, ou os arquivos que você está prestes a considerar como "prontos"). Se o escopo for pequeno (poucos arquivos, mudança isolada), você pode aplicar o checklist abaixo diretamente, sem subagente.

2. **Delegar a análise** ao subagente `lgpd-reviewer` (Agent tool, `subagent_type: "lgpd-reviewer"`) quando o escopo for maior que uma mudança trivial — ele é somente-leitura e conhece os 10 eixos de LGPD auditados no projeto (base legal, consentimento, acesso/portabilidade, eliminação, minimização/segurança, governança/auditoria, menores, retenção, terceiros/transferência internacional, painel admin), além dos anti-padrões já corrigidos que não podem voltar. Passe a ele: quais arquivos mudaram, o que a tarefa pretende fazer, e peça achados no formato `[severidade] arquivo:linha — problema — cenário de falha — ação recomendada`.

3. **Reportar ao usuário**: resuma os achados por severidade. Se algo for crítico (segredo hardcoded, rota sem controle de acesso, PII em texto plano sem necessidade), trate como bloqueante — não declare a tarefa concluída sem ao menos mencionar o achado e o que fazer a respeito. Achados de menor severidade (ex.: falta um aviso de finalidade, retenção não definida) podem virar itens de backlog em vez de bloquear a entrega, a critério do usuário.

4. **Não duplique auditoria já feita**: se o achado já está documentado na memória de projeto `gamo-lgpd-audit` como um item de backlog P1/P2 conhecido (ex.: falta consentimento no cadastro, sem export de dados, sem verificação de idade) e a tarefa atual não é sobre consertar aquilo especificamente, apenas cite que o gap é conhecido — não é preciso re-explicar o achado inteiro.
