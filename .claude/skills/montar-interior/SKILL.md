---
name: montar-interior
description: Como montar (ou refazer) um interior/mapa do gamo-city com peças do LimeZu e ficar bonito de primeira — piso certo, cômodos cheios como na referência, kits modulares (bancada, tapete), escada lateral pronta, tudo alinhado pela base, prévia conferida cômodo a cômodo. Use sempre que for construir ou mexer num mapa/casa/cômodo do City (gerador em scripts/maps, planta em art-src, Tiled), inclusive quando o usuário mandar uma referência de interior. Nasceu da casa de Julia (2026-11-11), que o Mateus achou fraca na 1ª versão e "outro nível" na 2ª.
---

# /montar-interior

Interior do Gamo City montado com o LimeZu (Modern Interiors / Modern Office). A regra 12 do
`gamo-city/AGENTS.md` vale sempre: **só peça original em 1:1** (recortar e colar pode; desenhar,
esticar ou redimensionar não). Faltou peça → procurar mais (folha geral!) e, se não existir,
perguntar ao Mateus. Base técnica (paredes, portas, faixas, estações) em `gamo-city/AGENTS.md` ›
"Interiores: como construir"; exemplo completo em `scripts/maps/build_julia_house.py` +
`art-src/julia-house-layout.json` + `scripts/houseDesign.ts`.

## O que fez a diferença (casa de Julia, v1 → v2)

A 1ª versão foi recusada por: poucos itens de cozinha, mesas pobres, sem banheiro, escada "subindo
para o nada", tapetes feios, recortes errados, piso manchado, porta desalinhada. A 2ª foi aprovada.
O que mudou é a lista abaixo — siga toda vez.

### 1. Piso

- Cada bloco **3×2** do `Room_Builder_Floors_16x16` é **UM piso**: (cx,cy) = canto de sombra,
  (cx+1,cy) = sombra da parede de cima, (cx,cy+1) = sombra da parede da esquerda, **(cx+1,cy+1) = piso
  limpo**. Repetir o bloco inteiro deixa o piso manchado (era o erro). Use `shadedFloor` (cômodo:
  sombra em cima e à esquerda) e `plainFloor` (passagens: só o limpo) de `scripts/houseDesign.ts`.
- Um piso por cômodo, escolhido entre as várias texturas bonitas da folha (madeira, xadrez da
  cozinha, ladrilho do banheiro) — conferir a prancha da folha antes de escolher.
- **Sem camada de chão** no `.tmj` por cima do cenário (ela cobria o piso desenhado).
- Passagens (corredor → cômodo, vãos de porta) desenhadas **depois** das paredes, senão aparecem
  como parede e o boneco "atravessa a parede" (parecia porta desalinhada).

### 2. Cômodo cheio como na referência

Antes de montar, liste por cômodo o que a referência tem e procure cada item. Mínimo que funcionou:
- **Cozinha:** geladeira (2 portas, `12_Kitchen` 097, encostada e com a base alinhada às bancadas),
  bancadas do kit modular com pia, torradeira, escorredor, panela de arroz, micro-ondas; fogão
  **embaixo da coifa**; potes e panelas na parede; mesa posta com toalha, cadeiras e tapete.
- **Banheiro:** banheira, vaso, pia com espelho em cima, máquina de lavar, prateleira, tapete.
- **Sala/quarto/escritório:** estantes, tapete oriental embaixo do grupo de móveis, poltronas,
  abajur, quadros/janela na parede, plantas nos cantos, criado-mudo com abajur, globo, etc.
- **Entrada:** capacho, sapatos, espelho de pé, ganchos, aparador.

### 3. Onde estão as peças boas

- Não fique só nas folhas de tema: a **folha geral `Interiors_16x16.png`** tem os tapetes
  orientais (inteiros e modulares), poltronas (linhas ~374–381), passadeira, e a **escada lateral**.
- Biblioteca do editor (`public/assets/library/<pacote>/`): peças avulsas já recortadas
  (`int-3-bathroom`, `int-12-kitchen`, `int-20-japanese-interiors`, `int-26-condominium`...).
- Sempre montar **prancha de conferência** (fundo roxo `(150,120,170)`, zoom 4–8×, nome embaixo) e
  recortar pelo **px exato** da peça: recorte com sobra pega a vizinha (a coifa veio com um cooktop).

### 4. Peças compostas (colar originais, nunca desenhar)

- **Bancada** = tampo de 10 px (ponta esq./meio/ponta dir.) + frente de 11 px (ponta, portas,
  gavetas, ponta) + pia/eletrodomésticos colados por cima (`counter()` no gerador da Julia).
- **Tapete modular** = ponta esquerda + N módulos do meio + ponta direita (`rug_wide()`): é o uso
  previsto do pacote; aprovado na casa de Julia.
- **Mesa posta**: itens **centralizados e sem passar da borda** da toalha (2 no máximo numa mesa
  estreita); "comida jogada" na mesa foi reclamação.
- **Escada lateral** (`Interiors_16x16` px 173,6057,35,45): a peça **já tem os degraus** (base em
  zigue-zague) e o corrimão. Não desenhar degraus atrás (a 1ª tentativa desenhou uma rampa amarela
  com `putpixel` — erro). Encostada na parede e **bloqueada** (`footprintRows`): não há 2º andar.
  O `generators.test.ts` barra `putpixel`/`ImageDraw`/`.resize(` no gerador.

### 5. Alinhamento (o que o olho pega)

- Tudo pela **base**: geladeira, fogão e bancadas terminam na mesma linha (`nudge` em px).
- Enfeite de parede (`on_wall`): base 1 px abaixo da faixa (`sortY`), senão some atrás dela; mais
  alto na parede → margem transparente embaixo (`raised()`), nunca subir a base.
- Porta centralizada no corredor (x com fração, ex. 16.3125).
- Cadeiras **encostadas** na mesa; mesa **centralizada** no tapete; tapete com `ground` e
  `footprintRows: 0`.
- Nada na frente de passagem ou porta; quadro não pendurado em cima de vão.
- Peça que ficou sem uso sai do `library-props` (ids só crescem; exceção documentada no AGENTS).

### 6. Conferir antes de mostrar

1. `python scripts/maps/<gerador>.py` e `node scripts/import-assets.ts --background=<mapa>`.
2. Prévia como o jogo desenha: `py -3.12 scripts/maps/interior_preview.py <mapa> <saida.png>`
   (`--crop x,y,w,h` em tiles para um cômodo, `--zoom 6`, `--markers` para as interações).
3. Olhar **cada cômodo ampliado**: piso liso; nada sumindo atrás da parede; bases alinhadas;
   nada flutuando, cortado ou passando da borda; passagens livres; parece a referência?
4. Prévia inteira na Área de Trabalho do Mateus (`Desktop/casa-...`) para ele avaliar.
5. Teste do mapa (`maps.test.ts`): cômodos e portas alcançáveis do nascimento, objetos de missão ao
   alcance; mudou posição de missão → os dois catálogos (City e API) + `docs/mapa-das-missoes.md`.
6. `/city-review` (o `city-reviewer` confere regra 12 e o checklist acima) e `pnpm verify`.

## Erros que já cometemos (não repetir)

- Repetir o bloco 3×2 do piso inteiro (piso manchado) — e a casa do jogador (`HOUSE_HOME`) ainda
  tem isso: só corrigir com ok do Mateus.
- Camada de chão do jogo por cima do cenário.
- Passagem desenhada antes da parede (virou parede).
- Escada desenhada em código; escada subindo para o nada no meio do cômodo.
- Bancada larga demais cobrindo o fogão; fogão fora da coifa; geladeira estreita mais baixa que a
  bancada.
- Lareira com a chaminé furando a parede de cima (recortar a ponta com `box`).
- Itens de mesa espalhados e saindo da toalha; cadeira longe da mesa; tapete descentralizado.
