#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

echo "== Installation des dépendances (serveur Debian + BDD) =="
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
    mariadb-server \
    whiptail

ensure_whiptail

DEFAULT_USER="administrateur"

USER=$(ui_input "Utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

if id "$USER" >/dev/null 2>&1; then
    usermod -aG sudo "$USER"
else
    echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

ui_info "Reseau" "Configuration reseau (DHCP - LAN)"
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

DEFAULT_IFACE="enp0s3"
IFACE=$(ui_input "Interface" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet dhcp
EOF

ui_info "MariaDB" "Correction du Bind-Address (Ecoute sur 0.0.0.0)"
# Cette ligne cherche le bind-address 127.0.0.1 et le remplace par 0.0.0.0
# pour permettre les connexions depuis le serveur Web en DMZ.
CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$CONF_FILE" ]; then
    sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address            = 0.0.0.0/' "$CONF_FILE"
    echo "Configuration mise à jour dans $CONF_FILE"
else
    echo "Fichier de config MariaDB introuvable, vérifiez l'installation." >&2
fi

ui_info "Services" "Redemarrage des services"
systemctl restart networking
systemctl enable mariadb
systemctl restart mariadb

ui_msg "Termine" "Le serveur BDD est pret.\nNote: le DHCP n'etant pas configure, le serveur attend une IP."
if whiptail --title "Redemarrage" --yesno "Voulez-vous redemarrer le serveur maintenant ?" 10 70 --defaultno; then
    reboot now
fi
