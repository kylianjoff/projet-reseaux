#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES (adapte à ton plan d’adressage)
ADMIN_USER="administrateur"

IFACE="enp0s3"
SERVER_IP="192.168.20.13"
NETMASK="255.255.255.0"
GATEWAY="192.168.20.254"
DNS="192.168.20.1"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Lancer en root"; exit 1; }

echo "[1/6] Mise à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/6] Installation paquets"
apt-get install -y \
  sudo curl nano vim traceroute iputils-ping ca-certificates \
  net-tools iproute2 ifupdown chrony

echo "[3/6] Utilisateur admin"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER" || true

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

# Redémarrage réseau robuste
if systemctl is-active --quiet networking 2>/dev/null; then
  systemctl restart networking
elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
  systemctl restart NetworkManager
else
  ifdown "${IFACE}" || true
  ifup "${IFACE}" || true
fi

sleep 3

echo "[5/6] Configuration Chrony (serveur NTP)"

cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak.$(date +%s) 2>/dev/null || true

cat > /etc/chrony/chrony.conf <<'EOF'
# Serveurs NTP publics (amont)
pool 0.fr.pool.ntp.org iburst
pool 1.fr.pool.ntp.org iburst
pool 2.fr.pool.ntp.org iburst
pool 3.fr.pool.ntp.org iburst

# Ajustement rapide au démarrage
makestep 1 3

# Dérive de l’horloge
driftfile /var/lib/chrony/drift

# Autoriser les réseaux internes
allow 192.168.20.0/24
allow 192.168.10.0/24

# Logs
logdir /var/log/chrony
log measurements statistics tracking
EOF

echo "[6/6] Démarrage des services"
systemctl enable chrony
systemctl restart chrony

echo "-----------------------------------"
echo "Vérification NTP"
chronyc tracking || true
chronyc sources -v || true
echo "-----------------------------------"
echo "Serveur NTP opérationnel : ${SERVER_IP}"