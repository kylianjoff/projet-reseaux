#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES PROJET
ADMIN_USER="administrateur"
SERVER_IP="192.168.10.10"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
DNS="192.168.10.13"
NTP_SERVER="192.168.10.15" 

# Paramètres interfaces
NAT_IFACE="enp0s8"   # Interface NAT
IP_IFACE="enp0s3"    # Interface IP

WEB_REPO_URL="https://github.com/kylianjoff/projet-reseaux"
WEB_REPO_BRANCH="main"
WEB_REPO_SUBDIR="ressources/srv-web"
WEB_REPO_DIR="/opt/srv-web-repo"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Lancer en root"; exit 1; }

### DETECTION INTERFACE


echo "[1/8] Mise à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/8] Installation paquets (Apache + Git + Chrony)"
apt-get install -y \
    sudo curl nano vim traceroute iputils-ping ca-certificates \
    net-tools iproute2 ifupdown apache2 git rsync chrony

# --- CONFIGURATION NTP (AJOUT) ---
echo "[3/8] Synchronisation temporelle sur le NTP local"
cat > /etc/chrony/chrony.conf <<EOF
server $NTP_SERVER iburst
driftfile /var/lib/chrony/drift
makestep 1 3
EOF
systemctl restart chrony
# ---------------------------------

id "$ADMIN_USER" >/dev/null 2>&1 && /usr/sbin/usermod -aG sudo "$ADMIN_USER" || true

echo "[4/8] Configuration réseau statique sur $IP_IFACE et NAT sur $NAT_IFACE"
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# Interface IP (LAN/DMZ)
auto $IP_IFACE
iface $IP_IFACE inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS}

# Interface NAT
auto $NAT_IFACE
iface $NAT_IFACE inet dhcp
EOF

echo "[5/8] Configuration Apache"
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

echo "[6/8] Script de déploiement Git"
cat > /usr/local/bin/deploy-web.sh <<EOF
#!/bin/bash
set -euo pipefail
REPO_URL="${WEB_REPO_URL}"
REPO_BRANCH="${WEB_REPO_BRANCH}"
REPO_SUBDIR="${WEB_REPO_SUBDIR}"
REPO_DIR="${WEB_REPO_DIR}"
WEB_ROOT="/var/www/html"

if [ ! -d "\${REPO_DIR}/.git" ]; then
    git clone --branch "\${REPO_BRANCH}" --depth 1 "\${REPO_URL}" "\${REPO_DIR}"
else
    git -C "\${REPO_DIR}" fetch --depth 1 origin "\${REPO_BRANCH}"
    git -C "\${REPO_DIR}" reset --hard "origin/\${REPO_BRANCH}"
fi

SRC_DIR="\${REPO_DIR}/\${REPO_SUBDIR}"
if [ -d "\${SRC_DIR}" ]; then
    rsync -a --delete "\${SRC_DIR}/" "\${WEB_ROOT}/"
    chown -R www-data:www-data "\${WEB_ROOT}"
fi
EOF

chmod +x /usr/local/bin/deploy-web.sh
# On tente un premier déploiement (nécessite un accès internet via le Firewall)
/usr/local/bin/deploy-web.sh || echo "Warning: Premier déploiement Git échoué (vérifiez l'accès internet)"

echo "[7/8] Service systemd de déploiement auto"
cat > /etc/systemd/system/web-deploy.service <<EOF
[Unit]
Description=Deploy web content from Git
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/deploy-web.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable web-deploy.service

echo "[8/8] Démarrage services"
systemctl enable apache2
systemctl restart apache2
systemctl restart networking || true

echo "-----------------------------------"
echo "Serveur Web DMZ installé avec succès"
echo "IP : ${SERVER_IP}"
echo "DNS : ${DNS}"
echo "NTP : ${NTP_SERVER}"
echo "-----------------------------------"