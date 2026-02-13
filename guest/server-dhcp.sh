#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root
echo "================================="
echo " [1/6] Recherche de mises à jour "
echo "================================="
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
	echo "Mise à jour échouée, tentative avec --allow-releaseinfo-change..."
	apt-get update -y --allow-releaseinfo-change
fi
echo "============================================"
echo " [2/6] Installation des paquets nécessaires "
echo "============================================"
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
	isc-dhcp-server \
	whiptail

ensure_whiptail

DEFAULT_USER="administrateur"

USER=$(ui_input "[3/6] Configuration utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

if id "$USER" >/dev/null 2>&1; then
	usermod -aG sudo "$USER"
    echo "Utilisateur '$USER' ajouté au groupe sudo."
else
	echo "Utilisateur '$USER' introuvable, ajout au groupe sudo ignoré." >&2
fi

DEFAULT_IFACE="enp0s3"

IFACE=$(ui_input "[4/6] Interface" "Nom de l'interface reseau" "$DEFAULT_IFACE") || exit 1
SERVER_IP=$(ui_input "[4/6] Adresse IP" "Adresse IP du serveur DHCP" "192.168.20.2") || exit 1
NETMASK=$(ui_input "[4/6] Reseau" "Masque reseau" "255.255.255.0") || exit 1
GATEWAY=$(ui_input "[4/6] Reseau" "Passerelle" "192.168.20.254") || exit 1
DNS=$(ui_input "[4/6] DNS" "Serveurs DNS (separes par des virgules)" "1.1.1.1,8.8.8.8") || exit 1
RANGE_START=$(ui_input "[4/6] DHCP" "Plage DHCP - debut" "192.168.20.100") || exit 1
RANGE_END=$(ui_input "[4/6] DHCP" "Plage DHCP - fin" "192.168.20.200") || exit 1
DOMAIN_NAME=$(ui_input "[4/6] Domaine" "Nom de domaine (optionnel)" "") || exit 1

DNS_LIST=$(echo "$DNS" | tr ',' ' ')

SUBNET=$(ipcalc -n "$SERVER_IP" "$NETMASK" | awk -F= '/Network/ {print $2}')
BROADCAST=$(ipcalc -b "$SERVER_IP" "$NETMASK" | awk -F= '/Broadcast/ {print $2}')

ui_info "[4/6] Configuration reseau" "Configuration IP statique"
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

ui_info "[5/6] Configuration DHCP" "Configuration ISC DHCP"
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

ui_info "[5/6] Configuration DHCP" "Definition de l'interface DHCP"
if [ -f /etc/default/isc-dhcp-server ]; then
	cp /etc/default/isc-dhcp-server /etc/default/isc-dhcp-server.bak.$(date +%s)
fi

cat > /etc/default/isc-dhcp-server <<EOF
INTERFACESv4="${IFACE}"
EOF

ui_info "[6/6] Services" "Redemarrage des services"
systemctl restart networking
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

ui_msg "Termine" "Verifiez le statut avec: systemctl status isc-dhcp-server\nRedemarrez le serveur pour appliquer toutes les configurations."
if whiptail --title "Redemarrage" --yesno "Voulez-vous redemarrer le serveur maintenant ?" 10 70 --defaultyes; then
    reboot now
fi