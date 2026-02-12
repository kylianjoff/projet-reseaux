#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
# =========================================
# Configuration du SERVEUR OpenVPN
# =========================================
# Réseau : DMZ (192.168.10.0/24)
# IP : 192.168.10.12
# Service : OpenVPN Server (Port 1194/UDP)

echo "========================================="
echo " Configuration du SERVEUR OpenVPN"
echo "========================================="

# Vérification root
require_root

apt update -y
apt install -y whiptail

ensure_whiptail

ui_info "Etape 0/12" "Preparation installation non interactive"
export DEBIAN_FRONTEND=noninteractive

# =========================================
# [1/12] Configuration Réseau DMZ
# =========================================
ui_info "Etape 1/12" "Configuration reseau DMZ fixe"

# Détection interface réseau (exclure lo et interfaces down)
ETH_DMZ=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
echo "Interface DMZ détectée : $ETH_DMZ"

# Configuration IP statique
ip addr flush dev $ETH_DMZ
ip addr add 192.168.10.12/24 dev $ETH_DMZ
ip link set $ETH_DMZ up

# Passerelle DMZ (Firewall Externe)
ip route add default via 192.168.10.254

# Configuration DNS
echo "nameserver 192.168.10.13" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Rendre la configuration persistante
cat > /etc/network/interfaces.d/$ETH_DMZ << EOF
auto $ETH_DMZ
iface $ETH_DMZ inet static
    address 192.168.10.12
    netmask 255.255.255.0
    gateway 192.168.10.254
    dns-nameservers 192.168.10.13 8.8.8.8
EOF

echo "✅ Réseau DMZ configuré : 192.168.10.12/24"

# =========================================
# [2/12] Mise à Jour Système
# =========================================
ui_info "Etape 2/12" "Mise a jour des paquets"
apt upgrade -y

# =========================================
# [3/12] Installation OpenVPN et Easy-RSA
# =========================================
ui_info "Etape 3/12" "Installation OpenVPN et Easy-RSA"
apt install -y openvpn easy-rsa iptables ufw

# Vérification installation
if ! command -v openvpn &> /dev/null; then
    echo "❌ Erreur : OpenVPN n'est pas installé correctement."
    exit 1
fi

echo "✅ OpenVPN installé : $(openvpn --version | head -n1)"

# =========================================
# [4/12] Configuration Easy-RSA (PKI)
# =========================================
ui_info "Etape 4/12" "Configuration de l'infrastructure PKI"

# Créer répertoire Easy-RSA
mkdir -p /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Copier les scripts Easy-RSA
cp -r /usr/share/easy-rsa/* .

# Initialiser PKI
./easyrsa init-pki

# Variables pour les certificats
cat > pki/vars << 'EOF'
set_var EASYRSA_REQ_COUNTRY    "FR"
set_var EASYRSA_REQ_PROVINCE   "IDF"
set_var EASYRSA_REQ_CITY       "Paris"
set_var EASYRSA_REQ_ORG        "Projet Reseau"
set_var EASYRSA_REQ_EMAIL      "admin@projet.local"
set_var EASYRSA_REQ_OU         "IT"
set_var EASYRSA_ALGO           "rsa"
set_var EASYRSA_KEY_SIZE       2048
EOF

echo "✅ PKI initialisée"

# =========================================
# [5/12] Génération Certificats
# =========================================
ui_info "Etape 5/12" "Generation des certificats (CA, Serveur, Clients)"

# Générer CA (Certificate Authority)
echo "Génération du certificat CA..."
./easyrsa --batch build-ca nopass

# Générer certificat et clé serveur
echo "Génération du certificat serveur..."
./easyrsa --batch build-server-full server nopass

# Générer certificats clients
echo "Génération des certificats clients..."
./easyrsa --batch build-client-full client1 nopass
./easyrsa --batch build-client-full client2 nopass

# Générer paramètres Diffie-Hellman (peut prendre 2-5 minutes)
echo "Génération des paramètres DH (patience...)..."
./easyrsa gen-dh

# Générer clé TLS-Auth pour sécurité supplémentaire
echo "Génération clé TLS-Auth..."
openvpn --genkey secret /etc/openvpn/ta.key

echo "✅ Tous les certificats générés"

# =========================================
# [6/12] Copie des Certificats
# =========================================
ui_info "Etape 6/12" "Copie des certificats dans /etc/openvpn"

# Copier les fichiers nécessaires
cp pki/ca.crt /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
cp pki/dh.pem /etc/openvpn/

echo "✅ Certificats copiés"

# =========================================
# [7/12] Configuration OpenVPN Serveur
# =========================================
ui_info "Etape 7/12" "Creation du fichier de configuration OpenVPN"

cat > /etc/openvpn/server.conf << 'EOF'
# Configuration OpenVPN Server
# Projet Réseau - DMZ

# Port et protocole
port 1194
proto udp
dev tun

# Certificats et clés
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0

# Réseau VPN (172.30.1.0/24)
server 172.30.1.0 255.255.255.0

# Pool d'IP pour clients
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# Routes à pousser aux clients
# Permettre accès au LAN
push "route 192.168.20.0 255.255.255.0"
# Permettre accès à la DMZ
push "route 192.168.10.0 255.255.255.0"

# DNS pour les clients
push "dhcp-option DNS 192.168.20.11"
push "dhcp-option DNS 8.8.8.8"

# Permettre la communication entre clients VPN
client-to-client

# Keepalive (ping toutes les 10s, timeout après 120s)
keepalive 10 120

# Compression (optionnel)
comp-lzo

# Utilisateur/Groupe pour sécurité
user nobody
group nogroup

# Persistance
persist-key
persist-tun

# Logs
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3

# Sécurité
cipher AES-256-CBC
auth SHA256
EOF

# Créer répertoire logs
mkdir -p /var/log/openvpn

echo "✅ Configuration serveur créée"

# =========================================
# [8/12] Activation IP Forwarding
# =========================================
ui_info "Etape 8/12" "Activation du routage IP"

# Activer immédiatement
echo 1 > /proc/sys/net/ipv4/ip_forward

# Rendre persistant après reboot
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# Appliquer
sysctl -p

echo "✅ IP Forwarding activé"

# =========================================
# [9/12] Configuration Firewall (iptables)
# =========================================
ui_info "Etape 9/12" "Configuration du firewall"

# NAT pour le trafic VPN vers LAN/DMZ
iptables -t nat -A POSTROUTING -s 172.30.1.0/24 -o $ETH_DMZ -j MASQUERADE

# Autoriser le trafic VPN
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Autoriser OpenVPN port 1194/UDP
iptables -A INPUT -p udp --dport 1194 -j ACCEPT

# Sauvegarder les règles
apt install -y iptables-persistent
netfilter-persistent save

echo "✅ Firewall configuré"

# =========================================
# [10/12] Démarrage OpenVPN
# =========================================
ui_info "Etape 10/12" "Demarrage du service OpenVPN"

# Activer et démarrer le service
systemctl enable openvpn@server
systemctl start openvpn@server

# Attendre que le service démarre
sleep 3

# Vérifier le statut
systemctl status openvpn@server --no-pager

echo "✅ Service OpenVPN démarré"

# =========================================
# [11/12] Génération Fichiers Clients
# =========================================
ui_info "Etape 11/12" "Generation des fichiers de configuration clients"

# Répertoire pour les configs clients
mkdir -p /root/openvpn-clients

# Fonction pour créer config client
generate_client_config() {
    local CLIENT_NAME=$1
    
    cat > /root/openvpn-clients/${CLIENT_NAME}.ovpn << EOF
client
dev tun
proto udp

# IP publique du serveur VPN (à adapter)
remote 192.168.10.12 1194

resolv-retry infinite
nobind
persist-key
persist-tun

# Certificats embarqués
<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat /etc/openvpn/easy-rsa/pki/private/${CLIENT_NAME}.key)
</key>

<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>

key-direction 1

cipher AES-256-CBC
auth SHA256
comp-lzo
verb 3
EOF

    echo "✅ Fichier client créé : /root/openvpn-clients/${CLIENT_NAME}.ovpn"
}

# Générer configs pour client1 et client2
generate_client_config "client1"
generate_client_config "client2"

# Permissions
chmod 600 /root/openvpn-clients/*.ovpn

echo "✅ Fichiers clients générés dans /root/openvpn-clients/"

# =========================================
# [12/12] Tests et Vérifications
# =========================================
ui_info "Etape 12/12" "Tests de connectivite"

# Test interface VPN
if ip addr show tun0 &> /dev/null; then
    echo "✅ Interface tun0 créée"
    ip addr show tun0
else
    echo "⚠️  Interface tun0 non trouvée (vérifier logs)"
fi

# Test ports
echo ""
echo "Ports en écoute :"
ss -tulnp | grep -E ':(1194)'

# Test ping réseau
echo ""
echo "Test ping vers autres serveurs DMZ :"
ping -c 2 192.168.10.254 || echo "⚠️  Firewall inaccessible"
ping -c 2 192.168.10.10 || echo "⚠️  Serveur Web inaccessible"
ping -c 2 192.168.10.11 || echo "⚠️  Serveur Mail inaccessible"

# =========================================
# Résumé Final
# =========================================
ui_msg "Termine" "Serveur OpenVPN configure avec succes.\nIP DMZ : 192.168.10.12/24\nPasserelle : 192.168.10.254\nPort OpenVPN : 1194/UDP\nReseau VPN : 172.30.1.0/24\n\nCertificats :\n- CA : /etc/openvpn/ca.crt\n- Serveur : /etc/openvpn/server.crt\n- DH : /etc/openvpn/dh.pem\n\nFichiers clients :\n- Client1 : /root/openvpn-clients/client1.ovpn\n- Client2 : /root/openvpn-clients/client2.ovpn\n\nRoutes poussees :\n- LAN : 192.168.20.0/24\n- DMZ : 192.168.10.0/24\n\nCommandes utiles :\n- Statut : systemctl status openvpn@server\n- Logs : tail -f /var/log/openvpn/openvpn.log\n- Clients : cat /var/log/openvpn/openvpn-status.log\n\nDistribuer configs :\n- Copier /root/openvpn-clients/*.ovpn\n- Installer OpenVPN client\n- Importer le fichier .ovpn"
