#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES RÉSEAU (selon ton plan d’adressage)
ADMIN_USER="administrateur"
SERVER_IP="192.168.20.14"
NETMASK="255.255.255.0"
GATEWAY="192.168.20.254"
DNS="192.168.10.13"
NTP_SERVER="192.168.10.15"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Lancer en root"; exit 1; }


# Interfaces explicites
NAT_IFACE="enp0s8"
IP_IFACE="enp0s3"

echo "[1/6] Mise à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/6] Installation paquets"
apt-get install -y sudo rsync openssh-server nano vim net-tools iproute2 ifupdown chrony

echo "[3/6] Création utilisateur admin"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER"

# --- CONFIGURATION DU CLIENT NTP  ---
echo "[2/4] Configuration du client NTP"
cat > /etc/chrony/chrony.conf <<EOF
# Connexion vers le serveur NTP en DMZ
server $NTP_SERVER iburst

# Autorise la correction rapide au démarrage (si décalage > 1s sur les 3 premières mesures)
makestep 1 3

# Synchroniser l'horloge matérielle (RTC) du noyau
rtcsync

# Fichier de dérive et logs
driftfile /var/lib/chrony/drift
logdir /var/log/chrony

EOF
systemctl restart chrony
chronyc makestep
# ---------------------------------
# --- CONFIGURATION SYSLOG (AJOUT) ---
echo "[*] Configuration du client Syslog"
apt-get install -y rsyslog
cat >> /etc/rsyslog.conf <<EOF
*.* @192.168.20.15:514
EOF
systemctl restart rsyslog
# -------------------------------

echo "[4/6] Configuration réseau statique ($IP_IFACE et $NAT_IFACE)"

cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# Interface IP (LAN/DMZ)
auto $IP_IFACE
iface $IP_IFACE inet static
    address $SERVER_IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS

# Interface NAT
auto $NAT_IFACE
iface $NAT_IFACE inet dhcp
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

# --- FIN DE TOUTES LES CONFIGURATIONS ---
# Mise hors ligne de l'interface NAT (après toutes les installations)
ip link set dev "$NAT_IFACE" down
echo "Interface $NAT_IFACE désactivée (down)"

# Création d'un service systemd pour désactiver l'interface NAT à chaque démarrage
cat > /etc/systemd/system/disable-nat-iface.service <<EOF
[Unit]
Description=Disable NAT interface ($NAT_IFACE) au boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set dev $NAT_IFACE down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable disable-nat-iface.service