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

echo
echo "Dans quel réseau se trouve le serveur ?"
echo "1) DMZ (192.168.10.0/24)"
echo "2) LAN (192.168.20.0/24)"
read -r -p "Choix [1-2] (Défaut: 2): " NETWORK_CHOICE
NETWORK_CHOICE="${NETWORK_CHOICE:-2}"

if [ "$NETWORK_CHOICE" = "1" ]; then
    NETWORK_PREFIX="192.168.10."
    DEFAULT_GATEWAY="192.168.10.254"
else
    NETWORK_PREFIX="192.168.20."
    DEFAULT_GATEWAY="192.168.20.254"
fi

DEFAULT_IFACE="enp0s3"
DEFAULT_LAST_OCTET="10"
DEFAULT_NETMASK="255.255.255.0"

read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"
read -r -p "Dernier octet de l'adresse IP du serveur Web (Par défaut : ${DEFAULT_LAST_OCTET}): " LAST_OCTET
LAST_OCTET="${LAST_OCTET:-$DEFAULT_LAST_OCTET}"
SERVER_IP="${NETWORK_PREFIX}${LAST_OCTET}"
read -r -p "Masque réseau (Par défaut : ${DEFAULT_NETMASK}): " NETMASK
NETMASK="${NETMASK:-$DEFAULT_NETMASK}"
read -r -p "Passerelle (Par défaut : ${DEFAULT_GATEWAY}): " GATEWAY
GATEWAY="${GATEWAY:-$DEFAULT_GATEWAY}"
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
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
$( [ -n "$SERVER_NAME" ] && echo "    ServerName ${SERVER_NAME}" )
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

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
read -r -p "Voulez-vous redémarrer le serveur maintenant ? [O/N] : " REBOOT_CHOICE
REBOOT_CHOICE="${REBOOT_CHOICE:-N}"

if [ "$REBOOT_CHOICE" = "O" ]; then
    reboot now
fi