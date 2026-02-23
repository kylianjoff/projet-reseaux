#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

ADMIN_USER="administrateur"
SERVER_IP="192.168.10.13"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
FORWARDERS="1.1.1.1,8.8.8.8"
DOMAIN_NAME="dmz.home"
REVERSE_ZONE="10.168.192.in-addr.arpa"
HOSTNAME="srv-dns-ext"
HOST_IP="192.168.10.13"

[ "$EUID" -eq 0 ] || exit 1

IFACE=$(ip route | awk '/default/ {print $5; exit}')

apt-get update -y
apt-get install -y bind9 bind9utils dnsutils sudo passwd net-tools iproute2

id "$ADMIN_USER" >/dev/null 2>&1 && /usr/sbin/usermod -aG sudo "$ADMIN_USER" || true

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
 address $SERVER_IP
 netmask $NETMASK
 gateway $GATEWAY
 dns-nameservers $SERVER_IP
EOF

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

named-checkconf
named-checkzone "$DOMAIN_NAME" "/etc/bind/db.$DOMAIN_NAME"
named-checkzone "$REVERSE_ZONE" "/etc/bind/db.$REVERSE_ZONE"

systemctl enable named.service || true
systemctl restart named.service
systemctl restart networking || true