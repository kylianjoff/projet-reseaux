#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
echo "================================="
echo " [1/5] Recherche de mises à jour "
echo "================================="
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
    echo "Mise à jour échouée, tentative avec --allow-releaseinfo-change..."
    apt-get update -y --allow-releaseinfo-change
fi

echo "============================================"
echo " [2/5] Installation des paquets nécessaires "
echo "============================================"
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
    apache2 \
    whiptail

ensure_whiptail

DEFAULT_USER="administrateur"

USER=$(ui_input "[3/5] Réglage utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

if id "$USER" >/dev/null 2>&1; then
    usermod -aG sudo "$USER"
else
    echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

ui_info "[3/5] Configuration réseau" "Dans quel reseau se trouve le serveur ?"

NETWORK_CHOICE=$(ui_menu "[3/5] Configuration réseau" "Dans quel reseau se trouve le serveur ?" "1" \
    "DMZ (192.168.10.0/24)" \
    "LAN (192.168.20.0/24)") || exit 1

if [ "$NETWORK_CHOICE" = "1" ]; then
    NETWORK_PREFIX="192.168.10."
    DEFAULT_GATEWAY="192.168.10.254"
    DEFAULT_DNS="192.168.10.13"
else
    NETWORK_PREFIX="192.168.20."
    DEFAULT_GATEWAY="192.168.20.254"
    DEFAULT_DNS="192.168.20.10"
fi

DEFAULT_IFACE="enp0s3"
DEFAULT_LAST_OCTET="10"
DEFAULT_NETMASK="255.255.255.0"

IFACE=$(ui_input "[3/5] Configuration réseau" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1
LAST_OCTET=$(ui_input "[3/5] Configuration réseau" "Dernier octet de l'adresse IP du serveur Web" "$DEFAULT_LAST_OCTET") || exit 1
SERVER_IP="${NETWORK_PREFIX}${LAST_OCTET}"
NETMASK=$(ui_input "[3/5] Configuration réseau" "Masque reseau" "$DEFAULT_NETMASK") || exit 1
GATEWAY=$(ui_input "[3/5] Configuration réseau" "Passerelle" "$DEFAULT_GATEWAY") || exit 1
DNS=$(ui_input "[3/5] Configuration réseau" "Serveurs DNS" "$DEFAULT_DNS") || exit 1
DNS="${DNS:-$DEFAULT_DNS}"
SERVER_NAME=$(ui_input "[3/5] Configuration réseau" "Nom de domaine (optionnel)" "") || exit 1

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

ui_info "[3/5] Configuration réseau" "Configuration IP statique"
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

ui_info "[4/5] Configuration du serveur web" "Configuration Apache"
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

ui_info "[5/5] Services" "Redemarrage des services"
systemctl restart networking
systemctl enable apache2
systemctl restart apache2

ui_msg "Termine" "Acces: http://${SERVER_IP}/\nRedemarrez le serveur pour appliquer toutes les configurations."
if whiptail --title "Redemarrage" --yesno "Voulez-vous redemarrer le serveur maintenant ?" 10 70 --defaultyes; then
    reboot now
fi
