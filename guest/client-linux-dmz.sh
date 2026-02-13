#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

echo "== Installation des dépendances (Client Debian) =="
export DEBIAN_FRONTEND=noninteractive
echo "================================="
echo " [1/5] Recherche de mises à jour "
echo "================================="
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
    whiptail

ensure_whiptail

DEFAULT_USER="administrateur"
ui_info "[3/5] Utilisateur" "Ajout de l'utilisateur au groupe sudo"
USER=$(ui_input "Utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

if id "$USER" >/dev/null 2>&1; then
    usermod -aG sudo "$USER"
else
    echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi
ui_info "[4/5] Configuration de l'interface reseau"

NETWORK_PREFIX="192.168.10."
DEFAULT_GATEWAY="192.168.10.254"
DEFAULT_DNS="192.168.10.13"

DEFAULT_IFACE="enp0s3"
DEFAULT_LAST_OCTET="100"
DEFAULT_NETMASK="255.255.255.0"

IFACE=$(ui_input "Interface" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1
LAST_OCTET=$(ui_input "Adresse IP" "Dernier octet de l'adresse IP" "$DEFAULT_LAST_OCTET") || exit 1
SERVER_IP="${NETWORK_PREFIX}${LAST_OCTET}"
NETMASK=$(ui_input "Reseau" "Masque reseau" "$DEFAULT_NETMASK") || exit 1
GATEWAY=$(ui_input "Reseau" "Passerelle" "$DEFAULT_GATEWAY") || exit 1
DNS=$(ui_input "DNS" "Serveurs DNS" "$DEFAULT_DNS") || exit 1
DNS="${DNS:-$DEFAULT_DNS}"
SERVER_NAME=$(ui_input "Domaine" "Nom de domaine (optionnel)" "") || exit 1

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

ui_info "[4/5] Configuration réseau" "Configuration IP statique"
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

ui_info "[5/5] Services" "Redemarrage des services"
systemctl restart networking

ui_msg "Termine" "Redemarrez le client pour appliquer toutes les configurations."
if whiptail --title "Redemarrage" --yesno "Voulez-vous redemarrer le client maintenant ?" 10 70 --defaultyes; then
    reboot now
fi
