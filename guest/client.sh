#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Ce script doit être exécuté en root. (su - puis mot de passe root)" >&2
    exit 1
fi

echo "== Installation des dépendances (Client Debian) =="
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
    ifupdown

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
read -r -p "Choix [1-2] (Défaut: 1): " NETWORK_CHOICE
NETWORK_CHOICE="${NETWORK_CHOICE:-1}"

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
DEFAULT_LAST_OCTET="100"
DEFAULT_NETMASK="255.255.255.0"

read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"
if [ "$NETWORK_CHOICE" = "1" ]; then
    read -r -p "Dernier octet de l'adresse IP du serveur Web (Par défaut : ${DEFAULT_LAST_OCTET}): " LAST_OCTET
    LAST_OCTET="${LAST_OCTET:-$DEFAULT_LAST_OCTET}"
    SERVER_IP="${NETWORK_PREFIX}${LAST_OCTET}"
    read -r -p "Masque réseau (Par défaut : ${DEFAULT_NETMASK}): " NETMASK
    NETMASK="${NETMASK:-$DEFAULT_NETMASK}"
    read -r -p "Passerelle (Par défaut : ${DEFAULT_GATEWAY}): " GATEWAY
    GATEWAY="${GATEWAY:-$DEFAULT_GATEWAY}"
    read -r -p "Serveurs DNS (Défaut: ${DEFAULT_DNS}): " DNS
else
    echo "Le serveur est configuré pour utiliser DHCP sur le réseau LAN."
fi
DNS="${DNS:-$DEFAULT_DNS}"
read -r -p "Nom de domaine (optionnel, ex: web.lan.local): " SERVER_NAME

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

echo "== Configuration IP statique =="
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

if [ "$NETWORK_CHOICE" = "1" ]; then
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
else
    cat > /etc/network/interfaces <<EOF
    auto lo
    iface lo inet loopback

    auto ${IFACE}
    iface ${IFACE} inet dhcp
EOF
fi

echo "== Redémarrage des services =="
systemctl restart networking

echo "== Terminé =="
echo "Redémarrez le client pour appliquer toutes les configurations: reboot"
echo ""
read -r -p "Voulez-vous redémarrer le client maintenant ? [O/N] : " REBOOT_CHOICE
REBOOT_CHOICE="${REBOOT_CHOICE:-N}"

if [ "$REBOOT_CHOICE" = "O" ]; then
    reboot now
fi
