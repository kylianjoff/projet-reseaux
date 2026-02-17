#!/bin/bash
# Configuration du serveur Syslog centralisé (srv-syslog) - 192.168.20.15

if [ "${EUID}" -ne 0 ]; then
    echo "ERREUR : Lancez avec sudo"
    exit 1
fi

echo "== Configuration Réseau (IP Statique) =="
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto enp0s3
iface enp0s3 inet static
    address 192.168.20.15
    netmask 255.255.255.0
    gateway 192.168.20.254
EOF

echo "== Installation et Configuration de Rsyslog =="
apt-get update && apt-get install -y rsyslog

# Activer la réception des logs via UDP (port 514)
sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

# Créer un répertoire pour stocker les logs des machines distantes
mkdir -p /var/log/remote
chown syslog:adm /var/log/remote

# Configurer rsyslog pour trier les logs par nom de machine
cat > /etc/rsyslog.d/central.conf <<EOF
\$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& ~
EOF

echo "== Redémarrage des services =="
systemctl restart networking
systemctl restart rsyslog

echo "== Serveur Syslog prêt sur 192.168.20.15 =="
echo "== Fait par MED =="