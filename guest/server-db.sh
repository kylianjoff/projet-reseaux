#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES RÉSEAU (selon ton plan d’adressage)
ADMIN_USER="administrateur"
SERVER_IP="192.168.20.12"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
DNS="192.168.10.13"
IFACE="enp0s3"

# Vérification root
[ "$EUID" -eq 0 ] || { echo "Ce script doit être lancé en root"; exit 1; }

echo "== Installation des dépendances =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change
apt-get install -y sudo curl nano vim traceroute iputils-ping ca-certificates \
                   net-tools iproute2 ifupdown mariadb-server whiptail || true

# Création/utilisateur admin
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER" || true

echo "== Configuration réseau statique =="
# Backup de l'ancienne configuration
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

# Configuration statique
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS}
EOF

# Appliquer la configuration
ifdown ${IFACE} 2>/dev/null || true
ifup ${IFACE} || true
echo "Adresse IP statique appliquée à ${IFACE} : ${SERVER_IP}"

# Vérification réseau
ip addr show ${IFACE}
ping -c 2 ${GATEWAY} || echo "Attention : la passerelle n'est pas joignable"

echo "== Configuration MariaDB =="
CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$CONF_FILE" ]; then
    sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' "$CONF_FILE"
    echo "MariaDB configurée pour écouter sur 0.0.0.0"
fi

systemctl enable mariadb
systemctl restart mariadb

echo "== Script terminé : serveur prêt =="