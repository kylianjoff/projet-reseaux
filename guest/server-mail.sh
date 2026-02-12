#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

echo "========================================="
echo " Configuration du SERVEUR MAIL (Postfix/Dovecot)"
echo "========================================="

# Vérification root
require_root

export DEBIAN_FRONTEND=noninteractive

# Pré-configurer Postfix pour éviter les questions
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string mail.projet.local" | debconf-set-selections

apt update -y
apt install -y whiptail

ensure_whiptail

ui_info "Etape 0/9" "Preparation pour installation non interactive"
ui_info "Etape 1/9" "Configuration reseau DMZ fixe"
# Remplacer eth1 par l'interface DMZ de la VM
ETH_DMZ=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
echo "Interface DMZ détectée : $ETH_DMZ"

# Supprimer les anciennes IP et ajouter IP statique
ip addr flush dev $ETH_DMZ
ip addr add 192.168.10.11/24 dev $ETH_DMZ
ip link set $ETH_DMZ up

# Ajouter la passerelle DMZ
ip route add default via 192.168.10.254

ui_info "Etape 2/9" "Mise a jour des paquets"

ui_info "Etape 3/9" "Installation Postfix, Dovecot et mailutils"
apt install -y postfix dovecot-core mailutils

# Vérification que Postfix est installé
if ! command -v postconf &> /dev/null; then
    echo "Erreur : Postfix n'est pas installé correctement."
    exit 1
fi

ui_info "Etape 4/9" "Configuration Postfix"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "myhostname = mail.projet.local"
postconf -e "mydomain = projet.local"
postconf -e "myorigin = /etc/mailname"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24 192.168.20.0/24"

ui_info "Etape 5/9" "Configuration Dovecot (IMAP)"
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#port = 143/port = 143/' /etc/dovecot/conf.d/10-master.conf

ui_info "Etape 6/9" "Creation du Maildir pour administrateur"
if [ -d /home/administrateur ]; then
    maildirmake.dovecot /home/administrateur/Maildir
    chown -R administrateur:administrateur /home/administrateur/Maildir
fi

ui_info "Etape 7/9" "Demarrage et activation des services"
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

ui_info "Etape 8/9" "Verification ecoute sur les ports"
ss -tlnp | grep -E ':(25|143)'

ui_info "Etape 9/9" "Test ping vers passerelle DMZ et autres serveurs"
ping -c 2 192.168.10.254
ping -c 2 192.168.10.10  # HTTP
ping -c 2 192.168.10.13  # DNS externe

ui_msg "Termine" "Serveur MAIL configure avec succes.\nIP DMZ : 192.168.10.11/24\nPasserelle DMZ : 192.168.10.254\nSMTP : port 25\nIMAP : port 143\nAccessible depuis le LAN/DMZ."
