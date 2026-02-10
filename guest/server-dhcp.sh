#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
	echo "Ce script doit être exécuté en root. (su - puis mot de passe root)" >&2
	exit 1
fi

echo "== Installation des dépendances (serveur Debian + DHCP) =="
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
	ipcalc \
	ifupdown \
	isc-dhcp-server

DEFAULT_USER="administrateur"

echo
read -r -p "Nom de l'utilisateur administrateur (Par défaut : ${DEFAULT_USER}): " USER
USER="${USER:-$DEFAULT_USER}"

if id "$USER" >/dev/null 2>&1; then
	usermod -aG sudo "$USER"
    echo "Utilisateur '$USER' ajouté au groupe sudo."
else
	echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

DEFAULT_IFACE="enp0s3"

echo
read -r -p "Nom de l'interface réseau (Par défaut : ${DEFAULT_IFACE}): " IFACE
IFACE="${IFACE:-$DEFAULT_IFACE}"
read -r -p "Adresse IP du serveur DHCP (DMZ : 192.168.10.0/24 | LAN : 192.168.20.0/24): " SERVER_IP
read -r -p "Masque réseau (ex: 255.255.255.0): " NETMASK
read -r -p "Passerelle (DMZ : 192.168.10.254 | LAN : 192.168.20.254): " GATEWAY
read -r -p "Serveurs DNS (séparés par des virgules, ex: 1.1.1.1,8.8.8.8): " DNS
read -r -p "Plage DHCP - début (ex: 192.168.20.100): " RANGE_START
read -r -p "Plage DHCP - fin (ex: 192.168.20.200): " RANGE_END
read -r -p "Nom de domaine (optionnel, ex: lan.local): " DOMAIN_NAME

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

SUBNET=$(ipcalc -n "$SERVER_IP" "$NETMASK" | awk -F= '/Network/ {print $2}')
BROADCAST=$(ipcalc -b "$SERVER_IP" "$NETMASK" | awk -F= '/Broadcast/ {print $2}')

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

echo "== Configuration ISC DHCP =="
if [ -f /etc/dhcp/dhcpd.conf ]; then
	cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak.$(date +%s)
fi

{
	if [ -n "$DOMAIN_NAME" ]; then
		echo "option domain-name \"${DOMAIN_NAME}\";"
	fi
	if [ -n "$DNS_LIST" ]; then
		echo "option domain-name-servers ${DNS_LIST};"
	fi
} > /tmp/dhcp-options.conf

cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

$(cat /tmp/dhcp-options.conf)

subnet ${SUBNET} netmask ${NETMASK} {
	range ${RANGE_START} ${RANGE_END};
	option routers ${GATEWAY};
	option subnet-mask ${NETMASK};
	option broadcast-address ${BROADCAST};
}
EOF

rm -f /tmp/dhcp-options.conf

echo "== Définition de l'interface DHCP =="
if [ -f /etc/default/isc-dhcp-server ]; then
	cp /etc/default/isc-dhcp-server /etc/default/isc-dhcp-server.bak.$(date +%s)
fi

cat > /etc/default/isc-dhcp-server <<EOF
INTERFACESv4="${IFACE}"
EOF

echo "== Redémarrage des services =="
systemctl restart networking
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

echo "== Terminé =="
echo "Vérifiez le statut avec: systemctl status isc-dhcp-server"
echo ""
echo "Redémarrez le serveur pour appliquer toutes les configurations: reboot"
echo ""