# Teste local — Dreamcast na Arena

Pasta para você colocar seus arquivos **legalizados** durante testes.
Nada daqui vai pro git (ver `.gitignore`).

## Arquivos necessários

| Arquivo | Obrigatório | Descrição |
|---------|-------------|-----------|
| `seu-jogo.chd` | Sim | ROM do jogo (CHD de Dreamcast) |
| `dc_boot.bin` | Recomendado | BIOS principal do Dreamcast |
| `dc_flash.bin` | Recomendado | Flash/NVRAM da BIOS |

### MD5 esperados (Flycast/libretro)

- `dc_boot.bin` → `e10c53c2f8b90bab96ead2d368858623`
- `dc_flash.bin` → `0a93f7940c455905bea6e392dfde92a4`

## Como criar a partida no admin

1. Ligue a Arena (`gamo-admin` → Arena → Ligar Arena).
2. Console: **Dreamcast (.chd, .gdi ou .cdi + BIOS)**.
3. Selecione **todos** os arquivos de uma vez: o `.chd` (ou `.gdi` + bins) **e** os dois `.bin` da BIOS.
4. Crie a partida e abra o link do organizador primeiro.

## Formatos alternativos

- **CHD** (1 arquivo) — mais simples, recomendado.
- **GDI + BIN/RAW** — selecione o `.gdi` e todos os arquivos de track referenciados nele.
- **CDI** — um arquivo só, também funciona.

## Não commite ROM/BIOS

Esses arquivos são protegidos por direito autoral. Use só em testes locais
ou upload pontual por partida na Arena (mesma política do resto da plataforma).
