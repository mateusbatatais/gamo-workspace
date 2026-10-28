#!/usr/bin/env bash
# Destrói a instância criada pelo up.sh (para de cobrar).
# Uso: ./down.sh --yes   (o --yes é de propósito, pra não destruir por acidente)

set -euo pipefail
cd "$(dirname "$0")"
source ./.env

if [ "${1:-}" != "--yes" ]; then
  echo "Isso vai DESTRUIR permanentemente a instância. Rode com: ./down.sh --yes"
  exit 1
fi

if [ ! -f ./.last-instance-id ]; then
  echo "Não encontrei .last-instance-id. Rode manualmente:"
  echo "curl -H \"Authorization: Bearer \$VULTR_API_KEY\" https://api.vultr.com/v2/instances"
  exit 1
fi

INSTANCE_ID=$(cat ./.last-instance-id)
AUTH="Authorization: Bearer $VULTR_API_KEY"

echo "==> Destruindo instância $INSTANCE_ID..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "https://api.vultr.com/v2/instances/$INSTANCE_ID" -H "$AUTH")

if [ "$HTTP_CODE" = "204" ]; then
  echo "==> Destruída com sucesso. Cobrança encerrada."
  rm -f ./.last-instance-id ./.last-instance-ip
else
  echo "==> Resposta inesperada (HTTP $HTTP_CODE). Confirme no painel da Vultr."
fi
