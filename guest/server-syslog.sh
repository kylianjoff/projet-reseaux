#!/bin/bash
set -euo pipefail

### PARAMÈTRES RÉSEAU
ADMIN_USER="administrateur"
SERVER_IP="192.168.20.15"
NETMASK="255.255.255.0"
GATEWAY="192.168.20.254"   # interne, si besoin pour LAN
DNS="192.168.10.13"        # serveur DNS interne
NAT_GW="10.0.3.2"          # passerelle NAT pour Internet via enp0s8
NTP_SERVER="192.168.10.15"

LAN_IFACE="enp0s3"
NAT_IFACE="enp0s8"

# Vérification root
[ "$EUID" -eq 0 ] || { echo "ERREUR : lancez avec sudo"; exit 1; }


echo "== Installation des paquets essentiels =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change
apt-get install -y sudo curl nano vim traceroute iputils-ping ca-certificates \
    net-tools iproute2 ifupdown chrony rsyslog

echo "== Configuration interfaces réseau =="

# Désactiver NetworkManager temporairement si présent
systemctl stop NetworkManager 2>/dev/null || true
systemctl disable NetworkManager 2>/dev/null || true

# Backup configuration précédente
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

# Configurer LAN statique et NAT DHCP
cat > /etc/network/interfaces <<EOF
# Loopback
auto lo
iface lo inet loopback

# LAN
auto ${LAN_IFACE}
iface ${LAN_IFACE} inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS}

# NAT
auto ${NAT_IFACE}
iface ${NAT_IFACE} inet dhcp
EOF

# Appliquer configuration réseau
ip addr flush dev ${LAN_IFACE} 2>/dev/null || true
ip addr flush dev ${NAT_IFACE} 2>/dev/null || true
systemctl restart networking || true

# Nettoyage des routes par défaut
ip route del default 2>/dev/null || true

# Route par défaut via NAT pour Internet
ip route add default via ${NAT_GW} dev ${NAT_IFACE}

echo "== Installation et configuration Rsyslog =="
apt-get update && apt-get install -y rsyslog chrony

# Activer réception UDP 514
sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

# Créer répertoire pour logs distants
mkdir -p /var/log/remote
chown root:adm /var/log/remote
chmod 755 /var/log/remote

# Configuration Rsyslog pour trier logs par hostname et programme
cat > /etc/rsyslog.d/central.conf <<EOF
# Template pour logs distants
\$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"

# Rediriger tous les logs vers le template
*.* action(type="omfile" dynaFile="RemoteLogs")

# Ne pas écrire les logs distants localement
& stop
EOF

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
# Redémarrer Rsyslog
systemctl restart rsyslog

echo "== Vérifications =="

echo "1. Interfaces réseau :"
ip addr show ${LAN_IFACE} | grep "inet " || echo "❌ LAN non configurée"
ip addr show ${NAT_IFACE} | grep "inet " || echo "⚠ NAT non configurée"

echo "2. Routes par défaut :"
ip route

echo "3. Test ping Internet via NAT :"
if ping -c 2 8.8.8.8 &>/dev/null; then
    echo " Internet OK"
else
    echo " Pas d'accès Internet"
fi

echo "4. Service Rsyslog :"
if systemctl is-active --quiet rsyslog; then
    echo " Rsyslog actif"
else
    echo " Rsyslog inactif"
    systemctl status rsyslog --no-pager | head -10
fi

echo "5. Port UDP 514 :"
if ss -ulpn | grep -q 514; then
    echo " Rsyslog écoute sur UDP 514"
else
    echo " Rsyslog n'écoute pas sur UDP 514"
fi

echo "== Serveur Syslog centralisé prêt =="
echo "   - LAN : ${SERVER_IP}/24"
echo "   - NAT : DHCP (Internet)"
echo "   - Logs distants : /var/log/remote/"