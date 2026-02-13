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
DEFAULT_IFACE="enp0s3"

IFACE=$(ui_input "Interface" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1
ui_msg "Information" "Le client est configure pour utiliser DHCP sur le reseau LAN."

ui_info "[4/5] Configuration de l'interface reseau" "Configuration IP statique"
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet dhcp
EOF

ui_info "[5/5] Services" "Redemarrage des services"
systemctl restart networking

ui_msg "Termine" "Redemarrez le client pour appliquer toutes les configurations."
if whiptail --title "Redemarrage" --yesno "Voulez-vous redemarrer le client maintenant ?" 10 70; then
    reboot now
fi
