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
| Emblemas da camisa | (prompt: folha 4x4 de emblemas 16x16, fundo branco) | `import_emblems.py <img> <grade> <nomes>` → `estampas/` |
| Olhos (16 pares frente+lado) | `eyes_template.py` | `import_eyes.py <img> <célula:nome>...` → `olhos/` |
| Cabelos (12 por folha, frente/costas/lado) | `hair_template.py` | `import_hair.py [--cinza] <img> <nomes>` (acha os desenhos sozinho; `--cinza` se a IA pintou de cinza) → `cabelos/` |
| Marcas no rosto (16 pares frente+lado) | `eyes_template.py marcas` | `import_eyes.py --saida marcas <img> <célula:nome>...` → `marcas/` |
| Barbas (16 pares frente+lado) | `eyes_template.py barbas` | `import_eyes.py --saida barbas <img> <célula:nome>...` → `barbas/` |
| Costas (9 por folha, corpo inteiro frente/costas/lado) | `back_template.py` | `import_back.py <img> <célula:nome>...` → `costas/` (nome `asas-*`/`capa-*`/`jetpack*` = animado; `mochila*` aparece de frente) |
| Cabeças de animal (12 por folha, frente/costas/lado) | `hair_template.py cabecas` | `import_heads.py <img> <nomes>` → `cabecas/` (prompt: pelo no MESMO pêssego, detalhes em cinza, sem olhos; avulsa: `--celula`; olhos: `head_eyes.py`) |
| Rosto (16 pares frente+lado: óculos, viseiras, máscaras de olho) | `eyes_template.py rosto` | `import_eyes.py --saida rosto <img> <célula:nome>...` → `rosto/` (conferir se a IA não desceu a peça para a boca) |
| Máscaras/capacetes (12 por folha, 3 vistas) | `hair_template.py mascaras` | `import_heads.py --saida mascaras <img> <nomes>` → `mascaras/` (máscara em cinza = pintável; nada de capacete igual ao de filme) |
| Chapéus (12 por folha, 3 vistas, cinza) | `hair_template.py chapeus` | `import_heads.py --saida chapeus <img> <nomes>` → `chapeus/` |
| Emblemas de console | — (código) `make_console_emblems.py` (arte do City, sem logo) | — |

Roupa básica: `gamo-city/src/domain/avatar/hdOutfit.ts` (pinta pelo mapa; sem mapa, regra por
posição). Roupas extras por código (colete, cinto, suspensório, gola polo, blusa de frio, kimono, maiô/biquíni/sunga): `hdGarments.ts` (só região e cor; a pintura é a `paint` do `hdOutfit.ts`). Pele: `hdSkin.ts` (antes da roupa). Corpo feminino: `hdBody.ts` (por código, antes da
pele; só de frente, preso ao tronco do mapa de partes). Teste no jogo: `pnpm dev` → `http://localhost:5174/?hd=1` (`?hd=0` desliga).

## Erros que já cometemos (não repetir)

Recorte / importação:
- **Atividades** (2026-11-06): moldes `act_templates.py`, importar com `import_act.py <atividade>
  <direção> <img>` (a IA muda o espaçamento e desenha maior: o importador acha as MOLDURAS e as
  linhas-guia de cada célula e reencaixa; centraliza pela pele, não pela bola). Folha:
  `build_act_sheet.py` → `body/acts-sheet.png`. Arremesso: usa do 2º ao 7º quadro; de costas o
  1º é o parado (a bola na frente some atrás do corpo).
- **Mapa de partes que volta fora do molde** (vários moldes numa imagem, bonecos menores, quadro
  faltando): `import_parts_loose.py <img>` casa cada quadro pela silhueta da referência e corrige
  pernas (pela altura do parado), cueca (quadril) e cabeça (a do parado encaixada).
- **Rebarba e parte faltando em peça de rosto** (2026-11-06): o importador guardava pele retocada
  pela IA e ignorava o que passa do contorno da cabeça. `--saida rosto` agora usa `extract_face`.
  Depois de qualquer importação: `python scripts/character-hd/clean_pieces.py` (ponto solto até
  2 px; furo de importação nos capacetes listados em `HOLE_NAMES`) e `pnpm art:hd`. Conferir
  com a peça sobre a cabeça em VERMELHO (rebarba de pele aparece na hora).
- **Peça importada não aparece no jogo:** o jogo lê `public/assets/characters-hd/` (cópia +
  `manifest.json`). Depois de importar/ajustar qualquer peça: `pnpm art:hd` (o teste
  `hdManifest.test.ts` falha se esquecer). A montagem é uma só: `domain/avatar/hdCompose.ts`.
- **Folha de rosto em outra escala** (2026-11-06, rosto-2: a IA desenhou as cabeças a ~6,8 px por
  pixel em vez de 9,9): `import_eyes.py` leu só fundo branco. `regrid_faces.py <ia> <saida.png> <n>`
  reencaixa pela linha do alto da cabeça e depois importa a saída. Peça avulsa (2 vistas numa
  imagem): medir o pixel e colar na célula 1 de uma folha 1536x1024 do mesmo jeito.
- **Orelhas** (`import_heads.py --saida orelhas`): pedir no pêssego da pele; o importador guarda
  só o que está fora da nossa cabeça ou bem diferente dela (cor segue a pele por código). Na mesma
  folha, chapéus com `--saida chapeus` e capuz com `--saida mascaras`, com `-` nos outros nomes.
- **Caudas** (`import_back.py`, nome `cauda-*`): pedir no pêssego da pele; o importador não apaga
  o tom de pele dessas (`SKIN_OK`) e a cor segue a pele (`tintBack`).
- **Cabelo longo com chapéu:** `cutHairUnderHat` corta acima da aba (linha mais baixa em que o
  chapéu ainda é largo; ponta/pompom caídos não contam) e, abaixo, limita à largura da aba abrindo
  0,75 px por linha, com contorno na borda nova. Coroa/faixa não cortam.
- **Mapa de partes com "pé" na mão** (2026-11-06): sapato/meia pintavam pontos na mão (parado de lado,
  correndo, veículos). `python scripts/character-hd/fix_parts_hands.py` (idempotente) corrige o mapa
  do corpo e os de `veiculos/partes/`; rodar de novo depois de gerar mapa novo e refazer as montadas.
- **Personagem "tremendo" na bicicleta de lado:** a IA desenhou quadros 2–3 px para trás.
  `build_rider_sheets.py` (`STEADY_SIDE`) alinha o tronco na mediana dos 6 quadros.
- **Cabeça escapando do capacete** (nuca atrás de lado no veículo): `clipHeadToMask` (`hdFace.ts`)
  apaga a cabeça fora da largura do capacete, linha a linha; dentro dela (boca das máscaras
  abertas) e abaixo dele nada muda.
- **Cabelo que a IA manda PRETO numa folha cinza** (2026-11-06, espetado-pontas): trocar todo o
  escuro por cinza apaga o contorno (fica chapado, 5–15 tons). Clarear só o MIOLO (máscara do
  escuro erodida ~1 pixel da IA, `MinFilter`), manter contorno e traços internos pretos; se o
  desenho vier maior que os outros, diminuir a célula (~85%, alinhada embaixo) antes de importar.
  O importador precisa da folha inteira (célula sozinha não acha a grade): colar a célula tratada
  na folha original e passar `-` nos outros nomes.
- **Volume de lado (`hdSilhouette.ts`) some quando o braço passa na frente** da barriga/peito:
  é de propósito (o braço cobre); não "consertar" pintando por cima do braço.
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
- Emblema do peito: 9×8 px (o usuário pediu 1–2 px de margem no tronco de ~12×11), começando 2 linhas
  abaixo do topo do tronco, sem contorno forçado. Marca/personagem real
  (DC, Marvel, Nintendo...) é decisão do usuário: avisar do risco de marca; o ChatGPT costuma recusar.
- Bermuda saiu (ficava igual à calça).
- Olhos: pedir à IA desenhando NA cabeça (erra menos que no vazio) e guardar só a diferença; cor da
  íris por código (não pedir "olho azul" como estilo); expressão (bravo, surpreso...) não é estilo:
  fica para emote temporário.
- Cabelo: a IA redesenha as cabeças e muda a grade — o importador acha os desenhos pela mancha,
  não pela posição. Pedir tudo num castanho só (cor por código). Erros já vistos (2026-11-05):
  vista de lado desenhada virada para a ESQUERDA (cabelo caía no rosto → espelhar pela borda com
  pele); de costas sem rosto para prender, o encaixe subia e deixava a nuca careca (→ exigir que o
  desenho cubra a cabeça toda, mesma escala da frente); castanho quase preto lido como contorno e
  brilho claro lido como pele (buracos); sombra avermelhada do pescoço lida como cabelo (rabisco
  no queixo); tamanho do pixel medido desenho a desenho (ruído → cabelo flutuando). Conferir com
  `HAIR_DEBUG=<pasta>` e no estúdio (Parado e Andando) antes de commitar; "afro-puff" e
  "cacheado-volume" passar como "-".
- Peça de cabeça montada: a cabeça sobe 14–16 px no veículo; a busca de `headOffset` precisa de
  folga (24), senão trava no limite e a peça flutua.

Processo:
- Conferir **todas as direções e todos os quadros** depois de mudar uma regra (o erro dos patins de
  frente passou porque só a vista de lado foi olhada).
- Heredoc no Bash perde `\n`/barras: escrever arquivo com Write/Edit, não com `python - <<EOF` que
  contenha `"\n"`.
- `vitest`/`grep` em pipe esconde a saída até o fim; teste temporário em `src/` nunca com
  `cat > arquivo` sem entrada (fica esperando o teclado).
- Nada disso vai para produção: o modo `?hd` só existe no `pnpm dev` (`import.meta.env.DEV`).
