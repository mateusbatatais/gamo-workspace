#!/usr/bin/env bash
# Recria a arena com tmpfs limpo e carrega uma ROM local antes do worker iniciar
# (evita o bug do coordinator com lista de jogos vazia — ver README.md, Fase 5).
#
# Uso: ./load-rom.sh <IP_DA_INSTANCIA> <caminho-local-da-rom>
# Ex:  ./load-rom.sh 216.238.107.131 "/c/Users/Mateus/projetos/gamo/gamo-web/roms/stf2.smc"

set -euo pipefail

IP="${1:?Uso: ./load-rom.sh <IP> <caminho-da-rom>}"
ROM="${2:?Uso: ./load-rom.sh <IP> <caminho-da-rom>}"
ROM_NAME="$(basename "$ROM")"

if [ ! -f "$ROM" ]; then
  echo "ERRO: arquivo não encontrado: $ROM"
  exit 1
fi

echo "==> Derrubando container atual (tmpfs some com ele, de propósito)..."
ssh "root@$IP" 'cd /opt/arena && docker compose down' 2>&1 | grep -v "^ Network\|^ Container" || true

echo "==> Subindo container limpo (worker vai esperar o sinal /tmp/.rom-ready)..."
ssh "root@$IP" 'cd /opt/arena && docker compose up -d' 2>&1 | grep -v "^ Network\|^ Container" || true

echo "==> Aguardando Xvfb..."
sleep 3

echo "==> Enviando '$ROM_NAME' direto do seu PC pro tmpfs (nunca toca disco do servidor)..."
cat "$ROM" | ssh "root@$IP" "docker exec -i cloud-game-local sh -c 'cat > /usr/local/share/cloud-game/assets/games/$ROM_NAME'"

echo "==> Liberando o worker pra iniciar..."
ssh "root@$IP" 'docker exec cloud-game-local touch /tmp/.rom-ready'

sleep 4
echo "==> Biblioteca carregada:"
ssh "root@$IP" 'docker logs cloud-game-local 2>&1 | grep -A8 "Lib dump" | tail -8'

echo ""
echo "Pronto: http://$IP:8000"
