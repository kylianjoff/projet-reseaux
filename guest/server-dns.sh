#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
	echo "Ce script doit être exécuté en root. (su - puis mot de passe root)" >&2
	exit 1
fi

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
	dnsutils

DEFAULT_USER="administrateur"

echo
read -r -p "Nom de l'utilisateur administrateur (Par défaut : ${DEFAULT_USER}): " USER
USER="${USER:-$DEFAULT_USER}"

if id "$USER" >/dev/null 2>&1; then
	usermod -aG sudo "$USER"
else
	echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

DEFAULT_IFACE="enp0s3"

echo
read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"
read -r -p "Adresse IP du serveur DNS (ex: 192.168.20.2): " SERVER_IP
read -r -p "Masque réseau (ex: 255.255.255.0): " NETMASK
read -r -p "Passerelle (ex: 192.168.20.254): " GATEWAY
read -r -p "DNS amont (séparés par des virgules, ex: 1.1.1.1,8.8.8.8): " FORWARDERS
read -r -p "Nom de domaine (ex: lan.local): " DOMAIN_NAME
read -r -p "Zone reverse (ex: 20.168.192.in-addr.arpa): " REVERSE_ZONE
read -r -p "Nom d'hôte à créer (ex: srv-dns): " HOSTNAME
read -r -p "IP de l'hôte (ex: 192.168.20.2): " HOST_IP

FORWARDERS_LIST=$(echo "$FORWARDERS" | tr ',' ';')
DNS_LIST=$(echo "$SERVER_IP" | tr ',' ' ')

echo "== Configuration IP statique =="
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

echo "== Configuration Bind9 =="
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

echo "== Redémarrage des services =="
systemctl restart networking
systemctl enable bind9
systemctl restart bind9

echo "== Terminé =="
echo "Test: dig @${SERVER_IP} ${HOSTNAME}.${DOMAIN_NAME}"
echo "Redémarrez le serveur pour appliquer toutes les configurations: reboot"
echo ""