#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

echo "== Installation des dépendances (serveur Debian + DNS) =="
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
	echo "Mise à jour échouée, tentative avec --allow-releaseinfo-change..."
	apt-get update -y --allow-releaseinfo-change
fi
apt-get install -y \
	sudo \
	curl \
	nano \
	vim \
	traceroute \
	iputils-ping \
	ca-certificates \
	net-tools \
	iproute2 \
	ifupdown \
	bind9 \
	bind9utils \
	dnsutils \
	whiptail

ensure_whiptail

DEFAULT_USER="administrateur"

USER=$(ui_input "Utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

if id "$USER" >/dev/null 2>&1; then
	usermod -aG sudo "$USER"
else
	echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

DEFAULT_IFACE="enp0s3"

IFACE=$(ui_input "Interface" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1
SERVER_IP=$(ui_input "Adresse IP" "Adresse IP du serveur DNS" "192.168.20.2") || exit 1
NETMASK=$(ui_input "Reseau" "Masque reseau" "255.255.255.0") || exit 1
GATEWAY=$(ui_input "Reseau" "Passerelle" "192.168.20.254") || exit 1
FORWARDERS=$(ui_input "DNS" "DNS amont (separes par des virgules)" "1.1.1.1,8.8.8.8") || exit 1
DOMAIN_NAME=$(ui_input "Domaine" "Nom de domaine" "lan.local") || exit 1
REVERSE_ZONE=$(ui_input "Domaine" "Zone reverse" "20.168.192.in-addr.arpa") || exit 1
HOSTNAME=$(ui_input "Hote" "Nom d'hote a creer" "srv-dns") || exit 1
HOST_IP=$(ui_input "Hote" "IP de l'hote" "192.168.20.2") || exit 1

FORWARDERS_LIST=$(echo "$FORWARDERS" | tr ',' ';')
DNS_LIST=$(echo "$SERVER_IP" | tr ',' ' ')

ui_info "Reseau" "Configuration IP statique"
if [ -f /etc/network/interfaces ]; then
	cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
	address ${SERVER_IP}
	netmask ${NETMASK}
	gateway ${GATEWAY}
	dns-nameservers ${DNS_LIST}
EOF

ui_info "Bind9" "Configuration Bind9"
if [ -f /etc/bind/named.conf.options ]; then
	cp /etc/bind/named.conf.options /etc/bind/named.conf.options.bak.$(date +%s)
fi

cat > /etc/bind/named.conf.options <<EOF
options {
	directory "/var/cache/bind";
	recursion yes;
	allow-query { any; };
	forwarders { ${FORWARDERS_LIST}; };
	dnssec-validation auto;
	listen-on { any; };
	listen-on-v6 { any; };
};
EOF

cat > /etc/bind/named.conf.local <<EOF
zone "${DOMAIN_NAME}" {
	type master;
	file "/etc/bind/db.${DOMAIN_NAME}";
};

zone "${REVERSE_ZONE}" {
	type master;
	file "/etc/bind/db.${REVERSE_ZONE}";
};
EOF

HOST_LAST_OCTET="${HOST_IP##*.}"

cat > "/etc/bind/db.${DOMAIN_NAME}" <<EOF
\$TTL	604800
@   IN  SOA ns.${DOMAIN_NAME}. admin.${DOMAIN_NAME}. (
		2     ; Serial
		604800 ; Refresh
		86400  ; Retry
		2419200 ; Expire
		604800 ) ; Negative Cache TTL
;
@   IN  NS  ns.${DOMAIN_NAME}.
ns  IN  A   ${SERVER_IP}
${HOSTNAME} IN  A   ${HOST_IP}
EOF

cat > "/etc/bind/db.${REVERSE_ZONE}" <<EOF
\$TTL	604800
@   IN  SOA ns.${DOMAIN_NAME}. admin.${DOMAIN_NAME}. (
		2     ; Serial
		604800 ; Refresh
		86400  ; Retry
		2419200 ; Expire
		604800 ) ; Negative Cache TTL
;
@   IN  NS  ns.${DOMAIN_NAME}.
${HOST_LAST_OCTET} IN PTR ${HOSTNAME}.${DOMAIN_NAME}.
EOF

ui_info "Services" "Redemarrage des services"
systemctl restart networking
systemctl enable bind9
systemctl restart bind9

ui_msg "Termine" "Test: dig @${SERVER_IP} ${HOSTNAME}.${DOMAIN_NAME}\nRedemarrez le serveur pour appliquer toutes les configurations."