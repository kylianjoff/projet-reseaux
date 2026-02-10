#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Ce script doit être exécuté en root. (su - puis mot de passe root)" >&2
    exit 1
fi

echo "== Installation des dépendances (serveur Debian + Web) =="
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
    echo "Mise à jour échouée, tentative avec --allow-releaseinfo-change..."
    apt-get update -y --allow-releaseinfo-change
fi
apt-get install -y \
    sudo \
    curl \
    nano \
    vim \
    traceroute \
    iputils-ping \
    ca-certificates \
    net-tools \
    iproute2 \
    ifupdown \
    apache2

DEFAULT_USER="administrateur"

echo
read -r -p "Nom de l'utilisateur administrateur (Par défaut : ${DEFAULT_USER}): " USER
USER="${USER:-$DEFAULT_USER}"

if id "$USER" >/dev/null 2>&1; then
    usermod -aG sudo "$USER"
else
    echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

DEFAULT_IFACE="enp0s3"

echo
read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"
read -r -p "Adresse IP du serveur Web (ex: 192.168.20.10): " SERVER_IP
read -r -p "Masque réseau (ex: 255.255.255.0): " NETMASK
read -r -p "Passerelle (ex: 192.168.20.254): " GATEWAY
read -r -p "Serveurs DNS (séparés par des virgules, ex: 1.1.1.1,8.8.8.8): " DNS
read -r -p "Nom de domaine (optionnel, ex: web.lan.local): " SERVER_NAME

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

echo "== Configuration IP statique =="
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS_LIST}
EOF

echo "== Configuration Apache =="
if [ -n "$SERVER_NAME" ]; then
    cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog \/var\/log\/apache2\/error.log
    CustomLog \/var\/log\/apache2\/access.log combined
</VirtualHost>
EOF
fi

cat > /var/www/html/index.html <<EOF
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>Serveur Web</title>
</head>
<body>
    <h1>Serveur Web opérationnel</h1>
    <p>Configuré par server-web.sh</p>
    <p>IP: ${SERVER_IP}</p>
</body>
</html>
EOF

echo "== Redémarrage des services =="
systemctl restart networking
systemctl enable apache2
systemctl restart apache2

echo "== Terminé =="
echo "Accès: http://${SERVER_IP}/"
echo "Redémarrez le serveur pour appliquer tous les configurations: reboot"
echo ""