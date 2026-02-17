#!/bin/bash
# Configuration du serveur NTP pour le projet réseau ISIMA
# Rôle : Serveur de temps central pour LAN et DMZ
# IP : 192.168.20.13

# 1. Vérification des droits root
if [ "$EUID" -ne 0 ]; then
    echo "ERREUR : Ce script doit être exécuté avec sudo (sudo ./server_ntp.sh)"
    exit 1
fi

# Détection automatique de l'interface réseau principale
IFACE=$(ip route | grep default | awk '{print $5}')

if [ -z "$IFACE" ]; then
    echo "ERREUR : Impossible de détecter l'interface réseau."
    exit 1
fi

echo "Interface réseau détectée : $IFACE"

echo "== Configuration du fuseau horaire (France) =="
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Fuseau horaire réglé sur Europe/Paris."

echo "== Configuration Réseau (IP Statique) =="
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

echo "== Installation et Configuration de Chrony (NTP) =="
apt-get update
apt-get install -y chrony

cat > /etc/chrony/chrony.conf <<EOF
# Serveurs de temps sources (Pool France)
pool fr.pool.ntp.org iburst

# Autoriser les réseaux du projet
allow 192.168.20.0/24   # LAN
allow 192.168.10.0/24   # DMZ

keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF

echo "== Redémarrage des services =="
systemctl restart networking || service networking restart
if systemctl list-units --type=service | grep -q chrony.service; then
    systemctl restart chrony
    systemctl enable chrony
elif systemctl list-units --type=service | grep -q chronyd.service; then
    systemctl restart chronyd
    systemctl enable chronyd
else
    echo "⚠️ Service Chrony introuvable (chrony / chronyd). Vérifie l'installation."
fi
echo "== Vérification du statut Chrony =="
chronyc sources -v

echo ""
echo "== Terminé ! Le serveur NTP est prêt sur 192.168.20.13 =="
echo "== Fait par MED =="
