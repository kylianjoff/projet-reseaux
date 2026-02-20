#!/bin/bash
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

### PARAMÈTRES PROJET (PLAN D’ADRESSAGE)
ADMIN_USER="administrateur"

SERVER_IP="192.168.10.10"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
DNS="192.168.10.13"

WEB_REPO_URL="https://github.com/kylianjoff/projet-reseaux"
WEB_REPO_BRANCH="main"
WEB_REPO_SUBDIR="ressources/srv-web"
WEB_REPO_DIR="/opt/srv-web-repo"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Lancer en root"; exit 1; }

### DETECTION INTERFACE
IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "[1/7] Mise à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || apt-get update -y --allow-releaseinfo-change

echo "[2/7] Installation paquets"
apt-get install -y \
    sudo curl nano vim traceroute iputils-ping ca-certificates \
    net-tools iproute2 ifupdown apache2 git rsync

id "$ADMIN_USER" >/dev/null 2>&1 && /usr/sbin/usermod -aG sudo "$ADMIN_USER" || true

echo "[3/7] Configuration réseau statique ($IFACE)"

cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS}
EOF

echo "[4/7] Configuration Apache"

cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

cat > /var/www/html/index.html <<EOF
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Serveur Web DMZ</title>
</head>
<body>
<h1>Serveur Web DMZ opérationnel</h1>
<p>IP : ${SERVER_IP}</p>
</body>
</html>
EOF

echo "[5/7] Script de déploiement Git"

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
[ -d "\${SRC_DIR}" ] || exit 1

rsync -a --delete "\${SRC_DIR}/" "\${WEB_ROOT}/"
chown -R www-data:www-data "\${WEB_ROOT}"
EOF

chmod +x /usr/local/bin/deploy-web.sh
/usr/local/bin/deploy-web.sh

echo "[6/7] Service systemd de déploiement auto"

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

echo "[7/7] Démarrage services"
systemctl enable apache2
systemctl restart apache2
systemctl restart networking || systemctl restart NetworkManager || true

echo "-----------------------------------"
echo "Serveur Web DMZ installé avec succès"
echo "Accès: http://${SERVER_IP}/"
echo "-----------------------------------"