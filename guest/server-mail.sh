#!/bin/bash

# Configuration du SERVEUR MAIL (Postfix/Dovecot)
# IP: 192.168.10.11 | DMZ

set -euo pipefail

### PARAMÈTRES
ADMIN_USER="administrateur"
SERVER_IP="192.168.10.11"
NETMASK="255.255.255.0"
GATEWAY="192.168.10.254"
DNS_SERVER="192.168.10.13"
NTP_SERVER="192.168.10.15"

DOMAIN="dmz.home"
HOSTNAME="mail"

### ROOT CHECK
[ "$EUID" -eq 0 ] || { echo "Erreur : Lancer en root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "[1/9] Configuration réseau statique"

# Interfaces explicites
NAT_IFACE="enp0s8"
IP_IFACE="enp0s3"

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# Interface IP (LAN/DMZ)
auto $IP_IFACE
iface $IP_IFACE inet static
    address $SERVER_IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVER

# Interface NAT
auto $NAT_IFACE
iface $NAT_IFACE inet dhcp
EOF

# Application immédiate pour l'installation des paquets
# (plus de manipulation directe d'IFACE, car les interfaces sont configurées ci-dessus)

echo "[2/9] Mise à jour et installation des paquets"
apt update -y
apt install -y postfix dovecot-core dovecot-imapd mailutils chrony whiptail sudo curl nano vim traceroute iputils-ping ca-certificates \
    net-tools iproute2 ifupdown rsyslog

id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER"

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
# ------------------------------------
# --- CONFIGURATION SYSLOG (AJOUT) ---
echo "[*] Configuration du client Syslog"
apt-get install -y rsyslog
cat >> /etc/rsyslog.conf <<EOF
*.* @192.168.20.15:514
EOF
systemctl restart rsyslog
# -------------------------------

echo "[4/9] Pré-configuration Postfix"
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string $HOSTNAME.$DOMAIN" | debconf-set-selections

echo "[5/9] Configuration Postfix (Main.cf)"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "myhostname = $HOSTNAME.$DOMAIN"
postconf -e "mydomain = $DOMAIN"
postconf -e "myorigin = /etc/mailname"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
# Autorise le relai pour la DMZ et le LAN
postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24 192.168.20.0/24"

echo "[6/9] Configuration Dovecot (IMAP)"
# Mailbox au format Maildir
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
# Autoriser l'authentification en clair pour le lab (port 143)
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf

echo "[7/9] Création du Maildir pour l'utilisateur $ADMIN_USER"
USER_HOME="/home/$ADMIN_USER"
if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/Maildir"/{cur,new,tmp}
    chown -R "$ADMIN_USER:$ADMIN_USER" "$USER_HOME/Maildir"
    chmod -R 700 "$USER_HOME/Maildir"
    echo "✓ Maildir créé dans $USER_HOME"
fi

echo "[8/9] Démarrage des services"
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

echo "[9/9] Vérification finale"
echo "--- État du NTP ---"
chronyc sources
echo "--- Ports en écoute (25 & 143) ---"
ss -tlnp | grep -E ':(25|143)'

echo "================================================="
echo " Serveur MAIL opérationnel sur $SERVER_IP"
echo " Hostname : $HOSTNAME.$DOMAIN"
echo " Synchronisé sur NTP : $NTP_SERVER"
echo "================================================="