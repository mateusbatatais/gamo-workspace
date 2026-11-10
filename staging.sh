#!/usr/bin/env bash
# Publica no STAGING (https://staging.gamo.games) a branch em que cada projeto ESTÁ AGORA.
# Roda no PC (Git Bash), na raiz do workspace:
#
#   ./staging.sh web              # o gamo-web, na branch atual dele
#   ./staging.sh api city web     # vários (sempre na ordem api → city → web)
#   ./staging.sh                  # todos os que NÃO estão em main/master
#   ./staging.sh web feat/x       # uma branch específica (só com um projeto)
#
# Só vai o que está COMMITADO (o build sai de um worktree limpo do commit); alteração sem commit
# fica de fora — o script avisa. Não precisa de push. Docker Desktop ligado para api/web.
# Quem faz o trabalho: gamo-api/deploy/staging/deploy-staging.sh (runbook no README de lá).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
DEPLOY="${STAGING_DEPLOY_SCRIPT:-$ROOT/gamo-api/deploy/staging/deploy-staging.sh}"
[ -f "$DEPLOY" ] || { echo "não achei $DEPLOY (a branch feat/staging do gamo-api já foi para o master?)" >&2; exit 1; }

declare -A REPO=([api]=gamo-api [city]=gamo-city [web]=gamo-web)
declare -A MAIN=([api]=master [city]=main [web]=main)

ARGS=("$@")
SERVICES=()
REF_OVERRIDE=""
for arg in "${ARGS[@]}"; do
  case "$arg" in
    api|city|web) SERVICES+=("$arg") ;;
    *) REF_OVERRIDE="$arg" ;;
  esac
done
if [ -n "$REF_OVERRIDE" ] && [ "${#SERVICES[@]}" -ne 1 ]; then
  echo "branch específica só com UM projeto (ex.: ./staging.sh web feat/x)" >&2; exit 1
fi
if [ "${#SERVICES[@]}" -eq 0 ]; then
  for s in api city web; do
    b="$(git -C "$ROOT/${REPO[$s]}" branch --show-current)"
    [ -n "$b" ] && [ "$b" != "${MAIN[$s]}" ] && SERVICES+=("$s")
  done
  [ "${#SERVICES[@]}" -gt 0 ] || { echo "todos os projetos estão em main/master: diga qual publicar (ex.: ./staging.sh web)" >&2; exit 1; }
fi

for s in api city web; do
  printf '%s\n' "${SERVICES[@]}" | grep -qx "$s" || continue
  repo="$ROOT/${REPO[$s]}"
  ref="${REF_OVERRIDE:-$(git -C "$repo" branch --show-current)}"
  [ -n "$ref" ] || { echo "$s: sem branch (HEAD solto) — passe a branch" >&2; exit 1; }
  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ] && [ -z "$REF_OVERRIDE" ]; then
    echo "⚠ $s: há alterações SEM commit em ${REPO[$s]} — elas NÃO vão para o staging"
  fi
  echo "▶ $s ← $ref"
  GAMO_ROOT="$ROOT" bash "$DEPLOY" "$s" "$ref"
done

echo
echo "Pronto: https://staging.gamo.games  (City: /city/)"
echo "Senha do portão: usuário gamo + a senha do staging. Contas: e-mail da equipe ou teste1..10@staging.gamo.games (mesma senha)."
