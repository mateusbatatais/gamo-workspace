#!/usr/bin/env bash
# Gera os links de teste (1 staff/organizador + N jogadores) pra uma partida.
# Isso é um substituto de teste pro que o gamo-api faria de verdade
# (POST /api/arena/session-token) -- mesmo formato de token, mesmo segredo.
#
# Uso: ./mint-tokens.sh <matchId> [numero-de-jogadores] [ip-do-servidor]
# Ex:  ./mint-tokens.sh partida-final-1 4 216.238.107.131

set -euo pipefail
cd "$(dirname "$0")"

MATCH_ID="${1:?Uso: ./mint-tokens.sh <matchId> [numero-de-jogadores] [ip]}"
NUM_PLAYERS="${2:-4}"
IP="${3:-216.238.107.131}"
SECRET=$(grep ARENA_JWT_SECRET .env.auth | cut -d= -f2)

sign() {
  local slot="$1" role="$2" nickname="$3"
  node -e "
    const crypto = require('crypto');
    function b64url(o) { return Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+\$/,''); }
    const header = { alg: 'HS256', typ: 'JWT' };
    const now = Math.floor(Date.now()/1000);
    const payload = { sub: $slot, matchId: '$MATCH_ID', slot: $slot, role: '$role', nickname: '$nickname', iss: 'gamo-api', aud: 'arena.gamo.games', iat: now, exp: now + 3600 };
    const data = b64url(header) + '.' + b64url(payload);
    const sig = crypto.createHmac('sha256', '$SECRET').update(data).digest('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+\$/,'');
    console.log(data + '.' + sig);
  "
}

echo "========================================"
echo " Partida: $MATCH_ID"
echo " Validade dos links: 1 hora"
echo "========================================"
echo ""
echo "--- ORGANIZADOR (staff — inicia a sala) ---"
STAFF_TOKEN=$(sign 1 staff Organizador)
echo "http://$IP:8000/?token=$STAFF_TOKEN"
echo ""

for i in $(seq 1 "$NUM_PLAYERS"); do
  echo "--- JOGADOR $i (controle $i) ---"
  PLAYER_TOKEN=$(sign "$i" player "Jogador$i")
  echo "http://$IP:8000/?token=$PLAYER_TOKEN"
  echo ""
done

echo "========================================"
echo " Ordem de uso:"
echo " 1. Abra o link do ORGANIZADOR primeiro (ele inicia a sala)."
echo " 2. Só depois abra os links dos jogadores (cada um entra"
echo "    automaticamente com o controle certo, um por dispositivo/aba)."
echo "========================================"
