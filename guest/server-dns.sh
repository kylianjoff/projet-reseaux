#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES
ADMIN_USER="administrateur"
SERVER_IP="192.168.10.13"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
FORWARDERS="1.1.1.1,8.8.8.8"
DOMAIN_NAME="dmz.home"
REVERSE_ZONE="10.168.192.in-addr.arpa"
HOSTNAME="srv-dns-ext"
HOST_IP="192.168.10.13"
NTP_SERVER="192.168.10.15"
NAT_IFACE="enp0s8"
IP_IFACE="enp0s3"

[ "$EUID" -eq 0 ] || exit 1

echo "[1/6] Installation des paquets (Bind9 + Chrony + Rsyslog)"
apt-get update -y
apt-get install -y bind9 bind9utils dnsutils sudo passwd net-tools iproute2 chrony rsyslog

echo "[2/6] Configuration réseau (LAN/DMZ + NAT)"
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
    dns-nameservers $SERVER_IP

# Interface NAT
auto $NAT_IFACE
iface $NAT_IFACE inet dhcp
EOF
systemctl restart networking || true

echo "[3/6] Configuration du client NTP (Chrony)"
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

echo "[4/6] Configuration du client Syslog"
cat >> /etc/rsyslog.conf <<EOF
*.* @192.168.20.15:514
EOF
systemctl restart rsyslog

echo "[5/6] Configuration Utilisateur"
id "$ADMIN_USER" >/dev/null 2>&1 && /usr/sbin/usermod -aG sudo "$ADMIN_USER" || true

echo "[6/6] Configuration BIND9"
FORWARDERS_LIST=$(echo "$FORWARDERS" | tr ',' ';')
cat > /etc/bind/named.conf.options <<EOF
options {
 directory "/var/cache/bind";
 recursion yes;
 allow-query { any; };
 forwarders { $FORWARDERS_LIST; };
 dnssec-validation auto;
 listen-on { any; };
 listen-on-v6 { any; };
};
EOF

cat > /etc/bind/named.conf.local <<EOF
zone "$DOMAIN_NAME" {
 type master;
 file "/etc/bind/db.$DOMAIN_NAME";
};
zone "$REVERSE_ZONE" {
 type master;
 file "/etc/bind/db.$REVERSE_ZONE";
};
EOF

cat > /etc/bind/db.$DOMAIN_NAME <<EOF
\$TTL 604800
@ IN SOA ns.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
  $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN_NAME.
ns IN A $SERVER_IP
srv-dns-ext IN A $HOST_IP
EOF

HOST_LAST_OCTET="${HOST_IP##*.}"
cat > /etc/bind/db.$REVERSE_ZONE <<EOF
\$TTL 604800
@ IN SOA ns.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
  $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN_NAME.
$HOST_LAST_OCTET IN PTR srv-dns-ext.$DOMAIN_NAME.
EOF

# Vérifications et redémarrage
named-checkconf
named-checkzone "$DOMAIN_NAME" "/etc/bind/db.$DOMAIN_NAME"
named-checkzone "$REVERSE_ZONE" "/etc/bind/db.$REVERSE_ZONE"
systemctl enable named.service || true
systemctl restart named.service

echo "------------------------------------------------"
echo "Serveur DNS configuré et synchronisé sur $NTP_SERVER"
echo "=================================================="
echo " Serveur DNS opérationnel sur $SERVER_IP"
echo " Domaine : $DOMAIN_NAME"
echo " Synchronisé sur NTP : $NTP_SERVER"

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
echo "=================================================="



echo "=================================================="
echo " Serveur DNS opérationnel sur $SERVER_IP"
echo " Domaine : $DOMAIN_NAME"
echo " Synchronisé sur NTP : $NTP_SERVER"
echo "=================================================="



# Mise hors ligne de l'interface NAT
ip link set dev "$NAT_IFACE" down
echo "Interface $NAT_IFACE désactivée (down)"
chronyc sources