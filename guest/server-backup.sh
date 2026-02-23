#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES RÉSEAU (selon ton plan d’adressage)
ADMIN_USER="administrateur"
SERVER_IP="192.168.20.14"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
DNS="192.168.10.13"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Lancer en root"; exit 1; }

### DETECTION INTERFACE
IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "[1/6] Mise à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/6] Installation paquets"
apt-get install -y sudo rsync openssh-server nano vim net-tools iproute2 ifupdown

echo "[3/6] Création utilisateur admin"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER"

echo "[4/6] Configuration réseau statique ($IFACE)"

cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

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

echo "[5/6] Préparation stockage sauvegardes"

mkdir -p /storage/backups
chown -R "$ADMIN_USER:$ADMIN_USER" /storage/backups
chmod 700 /storage/backups

echo "[6/6] Sécurisation SSH"

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

systemctl enable ssh
systemctl restart ssh

systemctl restart networking || systemctl restart NetworkManager || true

echo "-----------------------------------"
echo "Serveur Backup installé avec succès"
echo "IP: ${SERVER_IP}"
echo "Dossier sauvegardes: /storage/backups"
echo "-----------------------------------"