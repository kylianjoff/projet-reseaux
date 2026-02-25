#!/bin/bash
# Configuration d'un serveur NTP (Chrony) situé en DMZ
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES RÉSEAU (Adaptés à la DMZ 192.168.10.0/24)
ADMIN_USER="administrateur"
IFACE="enp0s3"
SERVER_IP="192.168.10.15"       # IP libre dans ta DMZ
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"        # Interface du Firewall-external
DNS="192.168.10.13"             # IP de ton srv-dns-ext

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Erreur : Lancer en root (sudo)"; exit 1; }

echo "[1/6] Mise à jour du système"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/6] Installation des paquets nécessaires"
apt-get install -y \
  sudo curl nano vim traceroute iputils-ping ca-certificates \
  net-tools iproute2 ifupdown chrony

echo "[3/6] Gestion de l'utilisateur admin"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin-ntp

echo "[4/6] Configuration du réseau statique en DMZ ($IFACE)"
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
 # --- CONFIGURATION SYSLOG (AJOUT) ---
echo "[*] Configuration du client Syslog"
apt-get install -y rsyslog
cat >> /etc/rsyslog.conf <<EOF
*.* @192.168.20.15:514
EOF
systemctl restart rsyslog
# -------------------------------
# Redémarrage du service réseau
systemctl restart networking || (ifdown "${IFACE}" && ifup "${IFACE}")
sleep 2

echo "[5/6] Configuration de Chrony (Serveur NTP de la DMZ)"
cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak.$(date +%s) 2>/dev/null || true

cat > /etc/chrony/chrony.conf <<EOF
# Serveurs de temps publics pour la synchronisation du serveur
pool 0.fr.pool.ntp.org iburst
pool 1.fr.pool.ntp.org iburst

# Tolérance de décalage au démarrage
makestep 1 3

# Fichier de dérive
driftfile /var/lib/chrony/drift

# --- SÉCURITÉ & ACCÈS ---
# Autoriser les machines de la DMZ
allow 192.168.10.0/24

# Autoriser les machines du réseau interne (LAN) via le Firewall-internal
allow 192.168.20.0/24

# Servir le temps même si le serveur n'est pas synchronisé (optionnel pour réseau isolé)
# local stratum 10

logdir /var/log/chrony
EOF

echo "[6/6] Activation et redémarrage du service"
systemctl enable chrony
systemctl restart chrony

echo "------------------------------------------------"
echo "Vérification de la synchronisation :"
chronyc tracking
echo "------------------------------------------------"
echo "Serveur NTP opérationnel en DMZ sur : ${SERVER_IP}"