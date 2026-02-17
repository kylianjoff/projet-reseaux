#!/bin/bash
# Configuration du serveur NTP pour le projet réseau ISIMA
# Rôle : Serveur de temps central pour LAN et DMZ
# IP : 192.168.20.13

# 1. Vérification des droits root
if [ "${EUID}" -ne 0 ]; then
    echo "ERREUR : Ce script doit être exécuté avec sudo (sudo ./server-ntp.sh)"
    exit 1
fi

echo "== Configuration du fuseau horaire (France) =="
# Méthode robuste sans timedatectl
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Fuseau horaire réglé sur Europe/Paris."

echo "== Configuration Réseau (IP Statique) =="
# Configuration de l'IP selon le plan : 192.168.20.13
# Gateway : Firewall-internal (192.168.20.254)
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto enp0s3
iface enp0s3 inet static
    address 192.168.20.13
    netmask 255.255.255.0
    gateway 192.168.20.254
EOF

echo "== Installation et Configuration de Chrony (NTP) =="
apt-get update
apt-get install -y chrony

# Configuration de chrony pour accepter les requêtes du LAN et de la DMZ
cat > /etc/chrony/chrony.conf <<EOF
# Serveurs de temps sources (Pool France pour précision maximale)
pool fr.pool.ntp.org iburst

# Autoriser les réseaux du projet selon le schéma
# LAN (Clients, Syslog, Backup, BDD)
allow 192.168.20.0/24
# DMZ (Web, Mail, DNS Externe)
allow 192.168.10.0/24

# Configuration technique locale
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF

echo "== Redémarrage des services =="
# On relance le réseau pour appliquer l'IP statique 192.168.20.13
systemctl restart networking
systemctl restart chrony
systemctl enable chrony

echo "== Vérification du statut =="
chronyc sources -v

echo ""
echo "== Terminé ! Le serveur NTP est prêt sur 192.168.20.13 =="
echo "== Fait par MED =="