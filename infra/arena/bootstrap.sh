#!/usr/bin/env bash
# Preparo inicial do servidor da Arena (Vultr, Ubuntu 22.04 LTS).
# Rodar uma vez, logo após o primeiro SSH na instância nova: sudo bash bootstrap.sh
#
# O que faz: instala Docker, desliga swap (necessário para a garantia de
# "ROM nunca toca disco" via tmpfs — ver infra/arena/README.md), configura
# firewall mínimo e instala o Caddy (proxy reverso com TLS automático).

set -euo pipefail

echo "==> Atualizando pacotes do sistema"
apt-get update -y
apt-get upgrade -y

echo "==> Desligando swap (RAM só, sem paginar pra disco)"
swapoff -a
# Comenta qualquer linha de swap no fstab pra não voltar no próximo boot
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

echo "==> Instalando Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

echo "==> Configurando firewall (ufw)"
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # Caddy - emissão/renovação TLS (HTTP-01)
ufw allow 443/tcp   # Caddy - HTTPS
ufw allow 443/udp   # Caddy - HTTP/3 (opcional, mas não atrapalha)
# Portas específicas do worker de emulação (coordinator/worker/WebRTC) serão
# adicionadas quando configurarmos o serviço de fato — não abrir nada às
# cegas antes de saber exatamente o que precisa ficar exposto.
ufw --force enable

echo "==> Instalando Caddy"
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy
systemctl enable --now caddy

echo "==> Criando diretório de trabalho"
mkdir -p /opt/arena
chmod 700 /opt/arena

echo ""
echo "==> Pronto. Verificações:"
docker --version
docker compose version
caddy version
free -h   # confirmar que 'Swap' aparece como 0B
echo ""
echo "Próximo passo: clonar o repositório do serviço de emulação em /opt/arena"
echo "e configurar o docker-compose real (isso a gente faz olhando o repo ao vivo,"
echo "não um arquivo pré-fabricado — ver infra/arena/README.md, Fase 4)."
