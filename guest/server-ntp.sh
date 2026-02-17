#!/bin/bash
set -euo pipefail

# Vérification des droits root
if [ "$EUID" -ne 0 ]; then
    echo "ERREUR : sudo requis"
    exit 1
fi

# Interface principale
IFACE=$(ip route | awk '/default/ {print $5}')
if [ -z "$IFACE" ]; then
    echo "ERREUR : impossible de détecter l'interface"
    exit 1
fi
echo "Interface détectée : $IFACE"

# Fuseau horaire
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Fuseau horaire : Europe/Paris"

# IP statique
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address 192.168.20.13
    netmask 255.255.255.0
    gateway 192.168.20.254
    dns-nameservers 1.1.1.1 8.8.8.8
EOF

# Redémarrage réseau fiable
if command -v ifdown >/dev/null 2>&1 && command -v ifup >/dev/null 2>&1; then
    ifdown $IFACE || true
    ifup $IFACE
else
    systemctl restart networking || true
fi

# Attente pour que l'interface soit UP
sleep 5

# Installation Chrony
apt-get update
apt-get install -y chrony

# Création des dossiers requis
mkdir -p /var/log/chrony
touch /etc/chrony/chrony.keys
chown chrony:chrony /var/log/chrony /etc/chrony/chrony.keys || true

# Configuration Chrony
cat > /etc/chrony/chrony.conf <<EOF
pool fr.pool.ntp.org iburst

allow 192.168.20.0/24
allow 192.168.10.0/24

keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF

# Redémarrage service
systemctl daemon-reload
if systemctl list-units --type=service | grep -q chrony.service; then
    systemctl restart chrony
    systemctl enable chrony
elif systemctl list-units --type=service | grep -q chronyd.service; then
    systemctl restart chronyd
    systemctl enable chronyd
else
    echo " Chrony introuvable"
fi

# Vérification
sleep 2
echo "== Statut Chrony =="
systemctl status chrony --no-pager || systemctl status chronyd --no-pager || true
echo "== Sources Chrony =="
chronyc sources -v || true

echo "== Serveur NTP prêt sur 192.168.20.13 =="
