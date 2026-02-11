#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Ce script doit être exécuté en root. (su - puis mot de passe root)" >&2
    exit 1
fi

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
    mariadb-server

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
echo "== Configuration Réseau (DHCP - LAN) =="
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

DEFAULT_IFACE="enp0s3"
read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet dhcp
EOF

echo "== Correction du Bind-Address (Ecoute sur 0.0.0.0) =="
# Cette ligne cherche le bind-address 127.0.0.1 et le remplace par 0.0.0.0
# pour permettre les connexions depuis le serveur Web en DMZ.
CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$CONF_FILE" ]; then
    sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address            = 0.0.0.0/' "$CONF_FILE"
    echo "Configuration mise à jour dans $CONF_FILE"
else
    echo "Fichier de config MariaDB introuvable, vérifiez l'installation." >&2
fi

echo "== Redémarrage des services =="
systemctl restart networking
systemctl enable mariadb
systemctl restart mariadb

echo "== Terminé =="
echo "Le serveur BDD est prêt."
echo "NOTE : Le DHCP n'étant pas configuré, le serveur attend une IP."
echo ""
read -r -p "Voulez-vous redémarrer le serveur maintenant ? [O/N] : " REBOOT_CHOICE
REBOOT_CHOICE="${REBOOT_CHOICE:-N}"

if [ "$REBOOT_CHOICE" = "O" ]; then
    reboot now
fi
