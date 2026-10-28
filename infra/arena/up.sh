#!/usr/bin/env bash
# Cria uma instância nova na Vultr, prepara o servidor e sobe o CloudRetro.
# Uso: ./up.sh
#
# Requer infra/arena/.env com VULTR_API_KEY=... (nunca comitar esse arquivo).

set -euo pipefail
cd "$(dirname "$0")"
source ./.env

REGION="sao"                                   # São Paulo, BR
PLAN="voc-c-2c-4gb-50s"                        # 2 vCPU / 4GB / CPU Optimized
OS_ID="2760"                                   # Ubuntu 26.04 LTS x64
SSHKEY_ID="f93ab869-163a-4567-8182-bff0f3a8bce7"
LABEL="arena-teste-$(date +%s 2>/dev/null || echo manual)"

AUTH="Authorization: Bearer $VULTR_API_KEY"

echo "==> Criando instância ($LABEL) em $REGION..."
CREATE_RESPONSE=$(curl -s -X POST "https://api.vultr.com/v2/instances" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"region\":\"$REGION\",\"plan\":\"$PLAN\",\"os_id\":$OS_ID,\"label\":\"$LABEL\",\"hostname\":\"$LABEL\",\"sshkey_id\":[\"$SSHKEY_ID\"],\"backups\":\"disabled\"}")

INSTANCE_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4)
if [ -z "$INSTANCE_ID" ]; then
  echo "ERRO ao criar instância. Resposta da API:"
  echo "$CREATE_RESPONSE"
  exit 1
fi
echo "==> Instância criada: $INSTANCE_ID"
echo "$INSTANCE_ID" > ./.last-instance-id

echo "==> Aguardando IP e status 'running' (isso leva ~30-90s)..."
IP=""
for i in $(seq 1 40); do
  INFO=$(curl -s "https://api.vultr.com/v2/instances/$INSTANCE_ID" -H "$AUTH")
  STATUS=$(echo "$INFO" | grep -o '"status":"[a-z]*"' | head -1 | cut -d'"' -f4)
  POWER=$(echo "$INFO" | grep -o '"power_status":"[a-z]*"' | head -1 | cut -d'"' -f4)
  CANDIDATE_IP=$(echo "$INFO" | grep -o '"main_ip":"[0-9.]*"' | head -1 | cut -d'"' -f4)
  if [ "$STATUS" = "active" ] && [ "$POWER" = "running" ] && [ "$CANDIDATE_IP" != "0.0.0.0" ] && [ -n "$CANDIDATE_IP" ]; then
    IP="$CANDIDATE_IP"
    break
  fi
  sleep 5
done

if [ -z "$IP" ]; then
  echo "ERRO: instância não ficou pronta a tempo. Verifique manualmente no painel Vultr (ID: $INSTANCE_ID)."
  exit 1
fi
echo "==> IP: $IP"
echo "$IP" > ./.last-instance-ip

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "==> Atualizando o DNS (arena.gamo.games -> $IP) na Cloudflare..."
  CF_AUTH="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
  ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=gamo.games" -H "$CF_AUTH" | grep -o '"id":"[a-f0-9]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$ZONE_ID" ]; then
    echo "AVISO: não consegui achar a zone gamo.games na Cloudflare -- aponte o DNS manualmente."
  else
    RECORD_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=arena.gamo.games" -H "$CF_AUTH" | grep -o '"id":"[a-f0-9]*"' | head -1 | cut -d'"' -f4)
    CF_BODY="{\"type\":\"A\",\"name\":\"arena.gamo.games\",\"content\":\"$IP\",\"ttl\":60,\"proxied\":false}"
    if [ -n "$RECORD_ID" ]; then
      curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "$CF_AUTH" -H "Content-Type: application/json" -d "$CF_BODY" >/dev/null
    else
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -H "$CF_AUTH" -H "Content-Type: application/json" -d "$CF_BODY" >/dev/null
    fi
    echo "==> DNS atualizado."
  fi
else
  echo "AVISO: CLOUDFLARE_API_TOKEN não configurado em .env -- aponte arena.gamo.games pra $IP manualmente."
fi

echo "==> Aguardando SSH responder..."
for i in $(seq 1 30); do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new root@"$IP" 'echo ok' >/dev/null 2>&1; then
    echo "==> SSH pronto."
    break
  fi
  sleep 5
done

echo "==> Copiando bootstrap.sh, docker-compose.yml, Caddyfile, servicos e overrides..."
scp -o StrictHostKeyChecking=accept-new ./bootstrap.sh root@"$IP":/root/bootstrap.sh
scp -o StrictHostKeyChecking=accept-new ./docker-compose.yml root@"$IP":/root/docker-compose.yml
scp -o StrictHostKeyChecking=accept-new ./Caddyfile root@"$IP":/root/Caddyfile
scp -o StrictHostKeyChecking=accept-new ./.env.auth root@"$IP":/root/.env.auth
scp -o StrictHostKeyChecking=accept-new ./.env.admin root@"$IP":/root/.env.admin
ssh root@"$IP" 'mkdir -p /root/auth-server /root/admin-server /root/overrides'
scp -o StrictHostKeyChecking=accept-new -r ./auth-server/. root@"$IP":/root/auth-server/
scp -o StrictHostKeyChecking=accept-new -r ./admin-server/. root@"$IP":/root/admin-server/
if [ -d ./overrides ]; then
  scp -o StrictHostKeyChecking=accept-new -r ./overrides/. root@"$IP":/root/overrides/
fi

echo "==> Rodando bootstrap.sh no servidor..."
ssh root@"$IP" 'bash /root/bootstrap.sh'

echo "==> Clonando CloudRetro, aplicando docker-compose/overrides..."
ssh root@"$IP" '
  rm -rf /opt/arena
  mkdir -p /opt/arena
  cd /opt/arena
  git clone --depth 1 https://github.com/giongto35/cloud-game.git .
  cp /root/docker-compose.yml /opt/arena/docker-compose.yml
  cp /root/.env.auth /opt/arena/.env.auth
  cp /root/.env.admin /opt/arena/.env.admin
  rm -rf /opt/arena/auth-server /opt/arena/admin-server
  cp -r /root/auth-server /opt/arena/auth-server
  cp -r /root/admin-server /opt/arena/admin-server
  if [ -d /root/overrides ] && [ -n "$(ls -A /root/overrides 2>/dev/null)" ]; then
    cp -rv /root/overrides/. /opt/arena/
  fi
  # Flycast (Dreamcast) precisa de libgomp.so.1 -- ver arenaServer.service.ts
  grep -q libgomp1 Dockerfile || sed -i "/libxext6/s/libxext6/libxext6 libgomp1/" Dockerfile
  grep -q libgomp1 Dockerfile
  docker compose up --build -d
  cp /root/Caddyfile /etc/caddy/Caddyfile
  systemctl reload caddy
'

echo "==> Abrindo portas no firewall..."
ssh root@"$IP" '
  ufw allow 9000/tcp comment "cloud-game worker" || true
  ufw allow 8443/udp comment "cloud-game webrtc" || true
  ufw allow 8081/tcp comment "arena-auth (via Caddy/TLS)" || true
  ufw allow 8082/tcp comment "arena-admin" || true
'

echo ""
echo "========================================"
echo " Servidor no ar (IP: $IP)."
echo ""
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo " AGORA aponte o registro A de arena.gamo.games pra esse IP no seu"
  echo " provedor de DNS (deixe DNS-only/sem proxy, ex.: nuvem cinza na"
  echo " Cloudflare) -- sem isso o Caddy não consegue emitir o certificado TLS"
  echo " e https://arena.gamo.games não funciona ainda."
  echo ""
fi
echo " Depois de propagar (geralmente < 1min), a arena fica em:"
echo " https://arena.gamo.games"
echo " (instance id: $INSTANCE_ID, salvo em .last-instance-id)"
echo "========================================"
