#!/usr/bin/env bash
# Clona (ou atualiza) os repos do Gamo lado a lado nesta pasta.
# Uso: ./bootstrap.sh   (roda no Git Bash no Windows)
set -euo pipefail

cd "$(dirname "$0")"

REPOS="gamo-api gamo-web gamo-app gamo-admin gamo-city"

for repo in $REPOS; do
  if [ -d "$repo/.git" ]; then
    echo "== $repo: já existe, git pull"
    git -C "$repo" pull --ff-only || echo "   (pull falhou; resolva à mão)"
  else
    echo "== $repo: clonando"
    git clone "https://github.com/mateusbatatais/$repo.git" "$repo"
  fi
done

echo
echo "Pronto. Lembre de criar os .env de cada projeto (não estão no git)."
