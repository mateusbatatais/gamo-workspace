---
name: fabrica-personagem
description: Padrão da Fábrica de Personagens do gamo-city (personagem 32×64 HD, branch feat/character-hd) — pedir arte à IA (ChatGPT) com moldes, importar, montar folhas, mapa de partes do corpo, roupa básica por código, veículos, patins e teste no jogo. Use sempre que for criar/refazer animação, pose, veículo montado, mapa de partes, roupa/estampa ou peça do personagem novo, ou quando o usuário mandar imagens devolvidas pela IA. Traz os prompts que funcionaram e a lista de erros que já cometemos.
---

# /fabrica-personagem

Personagem novo do Gamo City: 32×64 por quadro (o dobro de pixels do 16×32, mesmo espaço no
mundo), folha no layout do LimeZu (`HD_LAYOUT` em `gamo-city/src/content/avatar/hdLayout.ts`).
Tudo fica em `gamo-city/art-src/characters-hd/body/` e `gamo-city/scripts/character-hd/`.
A referência completa de como funciona está em `gamo-city/AGENTS.md`, seção "Fábrica de Personagens".
Este arquivo é o **como fazer** e o **o que não repetir**.

## Divisão de trabalho

- **A IA (ChatGPT, à mão pelo usuário, sem custo de API)** desenha: poses e animações novas, o
  personagem montado nos veículos e o **mapa de partes** (pintar a silhueta com cores chapadas).
- **O código** faz: recorte, alinhamento, limpeza, espelhar o lado esquerdo, montar folhas,
  respiração do parado, patins, roupa básica (pintada sobre o corpo pelo mapa) e cores.
- Nada de Gemini/API em massa sem estimativa e ok antes (regra do monorepo).

## Fluxo de um pedido à IA

1. Gerar o **molde** (script `*_templates.py`), que vai para `body/pedir-ia/` numerado. A pasta só
   tem o que falta pedir; o que já foi importado sai dela.
2. Mandar ao usuário **um prompt pronto por arquivo**, sem pedir para ele trocar texto. Uma
   conversa nova no GPT por imagem.
3. Quando a imagem volta (o usuário anexa; o caminho vem em `images/NN.png|jpg`): identificar
   qual molde é **pelo conteúdo** (direção, veículo) e importar com o `import_*.py` certo.
4. **Conferir visualmente** antes de dizer que ficou bom: prévia com o veículo colorido sobre um
   fundo que não confunda (o roxo `(150,120,170)`; o verde se confunde com patinete/grama), quadros
   lado a lado e também animado (GIF), e no estúdio pelo Playwright
   (`NODE_PATH=gamo-web/node_modules`; estúdio em `http://localhost:5174/tools/character-studio.html`).
5. `build_rider_sheets.py` se mexeu em veículo; `python scripts/character-hd/check_assets.py`
   (precisa sair sem ERRO); `pnpm verify`/hooks; commit + push na branch; docs no mesmo commit.
6. Responder com o que entrou, o que ficou com defeito (com honestidade) e o próximo pedido.

## Moldes e prompts que funcionaram

Regras gerais dos moldes:
- Formato **3:2 (1536×1024)** ou quadrado: é o que o ChatGPT devolve; outro formato ele distorce.
- Pixel do personagem = **bloco grande** (6–8 px) e o prompt diz o tamanho do bloco.
- Referência em cima, quadro a desenhar embaixo; o veículo do molde em **cinza claro** (o recorte
  trata como fundo); boneco-guia em cinza médio quando precisa de pose.
- Prompt em inglês, quadro a quadro, com movimentos pequenos ("foot lifted 2-4 px"); senão a IA
  exagera o passo.

Prompt-base (veículo, remada/pedalada) — usado em `vehicle_anim_templates.py`:
"Leave the light gray <vehicle> EXACTLY as it is: do not redraw it, do not outline it, do not
darken or recolor it. Draw only my character." + "Keep MY character exactly: same pixel size
(every pixel is a NxN block)… Do not copy the mannequins' shape, only their leg and arm position."
De frente/costas no skate/patinete: "feet close together ON the narrow deck; never one foot on each
side". Bicicleta: lista as 6 fases da pedalada, "the knee rises only a few pixels".

Prompt do **mapa de partes** (`parts_templates.py`) — o mesmo para todos os moldes de mapa; cores:
cabeça amarelo, tronco vermelho, braço verde, antebraço azul, mão roxo, quadril laranja, coxa
ciano, canela rosa, pé marrom. Frases que importam: "This is coloring only: do NOT move, redraw,
resize or reshape anything", "Keep the black outline pixels black", "Arm pixels that overlap the
torso belong to the arm. Seen from the side, the arm in front of the body belongs to the arm".
Até 6 quadros por molde; junte animações curtas no mesmo molde (`parado idle:down idle:up idle:right`).
O lado esquerdo **nunca** tem molde: é o direito espelhado.

## Comandos

| O quê | Molde | Importar |
|---|---|---|
| Caminhada | `walk_templates.py` | `import_walk.py <frente\|costas\|lado> <img>` |
| Sentado | `sit_template.py` | `import_pose.py sentado-lado <img>` |
| Dança | `dance_template.py` | `import_dance.py <img>` |
| Veículo parado (moto) | `vehicle_templates.py` | `import_vehicle.py <veículo> <img>` |
| Remada/pedalada | `vehicle_anim_templates.py [veículo]` | `import_vehicle.py <veículo> <img> <lado\|costas\|frente>` |
| Mapa de partes (a pé) | `parts_templates.py <nome> <anim:dir[:parte]>...` | `import_parts.py <img> <nome>` |
| Mapa de partes (montado) | `parts_templates.py <nome> rider:<veículo>:<dir>` | `import_parts.py <img> <nome>` |
| Patins | — (código) `make_roller.py` | — |
| Folha do corpo | `build_base_body.py` | — |
| Folhas montadas | `build_rider_sheets.py` (depois de qualquer import de veículo/mapa) | — |
| Checagem | `check_assets.py` | — |

Roupa básica: `gamo-city/src/domain/avatar/hdOutfit.ts` (pinta pelo mapa; sem mapa, regra por
posição). Teste no jogo: `pnpm dev` → `http://localhost:5174/?hd=1` (`?hd=0` desliga).

## Erros que já cometemos (não repetir)

Recorte / importação:
- **Cueca branca some** quando encosta no veículo cinza (o fundo "vaza" por ela): na bicicleta
  (`SEATED`) o recorte compara com o molde só DENTRO da caixa da cueca; fora dela isso cria
  bolsões brancos. Nunca ligar a comparação com o molde para todos os veículos.
- **Limpeza de linha-guia** (linhas da cabeça/pés) cortava a cintura nos moldes de veículo: moldes
  sem guia têm `"guides": false` na geometria.
- **A IA escurece/contorna o veículo** do molde: `clean_vehicle`; fiapos e pó: `drop_loose`;
  rebarba branca na borda: `clean_fringe` (protege claro ligado à pele = cueca).
- **Corpo desliza para o lado** de frente/costas ao remar: prender a cabeça no centro do veículo; no
  skate, prender o **pé de apoio** desde o 1º quadro (medir a borda direita da perna, não o centro
  do bloco das duas pernas coladas).
- **Contorno dobrado no alto da cabeça** (tampa grossa) em quadros da IA: `drop_double_top` no import
  da caminhada; `check_assets.py` acusa.
- A cueca pode aparecer **numa linha só** (perna levantada): achar a cueca pelo bloco com MAIS claro,
  não o mais comprido (uma sombra cinza nas costas também tem 2–3 claros).

Patins:
- Bota de lado pelo **cano no tornozelo** + apagar o pé que sobra fora da bota **só de lado**
  (de frente/costas a bota é estreita e o corte levou a canela junto — erro já cometido).
- Pé que sobe no impulso também ganha bota; pés colados de lado = um pedaço só → dividir em dois.

Roupa básica:
- Achar partes por posição falha quando braço/perna se mexe: **sempre cortar pelo mapa de partes**.
- Medir "quanto da manga/perna" a partir da parte anterior com folga de 2 px (de costas o contorno
  separa coxa e quadril; sem a folga a perna ficava sem calça).
- Sombra da roupa pela luz média 3×3 do corpo: some mamilo e resto da cueca. Contorno preto fica.
- Patins: a roupa não pinta os pés (a bota fica).
- Estampa (listra, xadrez, zíper) sempre presa ao topo/centro do tronco do quadro, nunca à
  coordenada do quadro: o corpo sobe 1 px ao respirar e a listra escorregaria.
- Zíper/aberta/desenho da frente só de frente; de lado e de costas não aparecem.

Processo:
- Conferir **todas as direções e todos os quadros** depois de mudar uma regra (o erro dos patins de
  frente passou porque só a vista de lado foi olhada).
- Heredoc no Bash perde `\n`/barras: escrever arquivo com Write/Edit, não com `python - <<EOF` que
  contenha `"\n"`.
- `vitest`/`grep` em pipe esconde a saída até o fim; teste temporário em `src/` nunca com
  `cat > arquivo` sem entrada (fica esperando o teclado).
- Nada disso vai para produção: o modo `?hd` só existe no `pnpm dev` (`import.meta.env.DEV`).
