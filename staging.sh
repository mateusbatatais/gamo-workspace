#!/usr/bin/env bash
# Publica no STAGING o que está COMMITADO na branch atual de cada projeto. Roda no PC.
#
#   ./staging.sh                  # menu: mostra os 4 projetos e a branch de cada um; escolha
#   ./staging.sh web              # direto: o gamo-web, na branch atual dele
#   ./staging.sh api city         # vários (sempre na ordem api → city → web → admin)
#   ./staging.sh web feat/x       # uma branch específica (só com um projeto)
#
# No Windows dá para dar dois cliques em staging.cmd (abre este menu).
# Endereços: https://staging.gamo.games (site, /city/) · https://admin-staging.gamo.games (admin)
# Não precisa de push. Alteração sem commit NÃO vai (o script avisa). Docker Desktop ligado para
# api e web. Quem faz o trabalho: deploy/staging/deploy-staging.sh do gamo-api, lido do
# origin/master (não depende de como está o seu checkout do gamo-api).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

ORDER=(api city web admin)
declare -A REPO=([api]=gamo-api [city]=gamo-city [web]=gamo-web [admin]=gamo-admin)
declare -A MAIN=([api]=master [city]=main [web]=main [admin]=master)
declare -A NAME=([api]="API + mundo do City" [city]="Gamo City" [web]="site" [admin]="painel admin")

# Script de publicação: sempre a versão do origin/master do gamo-api
DEPLOY="$(mktemp)"
trap 'rm -f "$DEPLOY"' EXIT
git -C "$ROOT/gamo-api" fetch -q origin master
git -C "$ROOT/gamo-api" show origin/master:deploy/staging/deploy-staging.sh > "$DEPLOY" 2>/dev/null \
  || { echo "o origin/master do gamo-api ainda não tem deploy/staging/deploy-staging.sh" >&2; exit 1; }

branch_of() { git -C "$ROOT/${REPO[$1]}" branch --show-current; }
dirty_of() { [ -n "$(git -C "$ROOT/${REPO[$1]}" status --porcelain --untracked-files=no)" ]; }

SERVICES=()
REF_OVERRIDE=""
for arg in "$@"; do
  case "$arg" in
    api|city|web|admin) SERVICES+=("$arg") ;;
    *) REF_OVERRIDE="$arg" ;;
  esac
done
if [ -n "$REF_OVERRIDE" ] && [ "${#SERVICES[@]}" -ne 1 ]; then
  echo "branch específica só com UM projeto (ex.: ./staging.sh web feat/x)" >&2; exit 1
fi

# Sem argumentos: menu
if [ "$#" -eq 0 ]; then
  echo "Publicar no staging — o que está commitado na branch atual de cada projeto:"
  echo
  i=1
  DEFAULT=()
  for s in "${ORDER[@]}"; do
    b="$(branch_of "$s")"
    note=""
    [ "$b" = "${MAIN[$s]}" ] && note=" (= produção)" || DEFAULT+=("$i")
    dirty_of "$s" && note="$note  ⚠ tem alteração sem commit (não vai)"
    printf '  %d) %-6s %-22s branch %s%s\n' "$i" "$s" "${NAME[$s]}" "${b:-?}" "$note"
    i=$((i + 1))
  done
  echo
  hint="${DEFAULT[*]:-}"
  read -r -p "Quais publicar? números separados por espaço${hint:+ [Enter = $hint]}: " picks
  picks="${picks:-$hint}"
  [ -n "$picks" ] || { echo "nada escolhido"; exit 0; }
  for n in $picks; do
    [[ "$n" =~ ^[1-4]$ ]] || { echo "opção inválida: $n" >&2; exit 1; }
    SERVICES+=("${ORDER[$((n - 1))]}")
  done
fi

for s in "${ORDER[@]}"; do
  printf '%s\n' "${SERVICES[@]}" | grep -qx "$s" || continue
  ref="${REF_OVERRIDE:-$(branch_of "$s")}"
  [ -n "$ref" ] || { echo "$s: sem branch (HEAD solto) — passe a branch" >&2; exit 1; }
  if [ -z "$REF_OVERRIDE" ] && dirty_of "$s"; then
    echo "⚠ $s: há alterações SEM commit em ${REPO[$s]} — elas NÃO vão para o staging"
  fi
  echo
  echo "▶ $s ← $ref"
  GAMO_ROOT="$ROOT" bash "$DEPLOY" "$s" "$ref"
done

echo
echo "Pronto."
echo "  Site e City: https://staging.gamo.games  (City em /city/)"
echo "  Admin:       https://admin-staging.gamo.games"
echo "  Contas: e-mail da equipe ou teste1..teste10@staging.gamo.games — senha em /opt/gamo/staging/.env (STAGING_PASSWORD)"
