#!/bin/bash

echo "========================================="
echo " Configuration du SERVEUR MAIL (Postfix/Dovecot)"
echo "========================================="

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en root."
  exit 1
fi

echo "[0/9] Préparation pour installation non interactive"
export DEBIAN_FRONTEND=noninteractive

# Pré-configurer Postfix pour éviter les questions
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string mail.projet.local" | debconf-set-selections

echo "[1/9] Configuration réseau DMZ fixe"
# Remplacer eth1 par l'interface DMZ de la VM
ETH_DMZ=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
echo "Interface DMZ détectée : $ETH_DMZ"

# Supprimer les anciennes IP et ajouter IP statique
ip addr flush dev $ETH_DMZ
ip addr add 192.168.10.11/24 dev $ETH_DMZ
ip link set $ETH_DMZ up

# Ajouter la passerelle DMZ
ip route add default via 192.168.10.254

echo "[2/9] Mise à jour des paquets"
apt update -y

echo "[3/9] Installation Postfix, Dovecot et mailutils"
apt install -y postfix dovecot-core mailutils

# Vérification que Postfix est installé
if ! command -v postconf &> /dev/null; then
    echo "Erreur : Postfix n'est pas installé correctement."
    exit 1
fi

echo "[4/9] Configuration Postfix"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "myhostname = mail.projet.local"
postconf -e "mydomain = projet.local"
postconf -e "myorigin = /etc/mailname"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24 192.168.20.0/24"

echo "[5/9] Configuration Dovecot (IMAP)"
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#port = 143/port = 143/' /etc/dovecot/conf.d/10-master.conf

echo "[6/9] Création du Maildir pour administrateur"
if [ -d /home/administrateur ]; then
    maildirmake.dovecot /home/administrateur/Maildir
    chown -R administrateur:administrateur /home/administrateur/Maildir
fi

echo "[7/9] Démarrage et activation des services"
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

echo "[8/9] Vérification écoute sur les ports"
ss -tlnp | grep -E ':(25|143)'

echo "[9/9] Test ping vers passerelle DMZ et autres serveurs"
ping -c 2 192.168.10.254
ping -c 2 192.168.10.10  # HTTP
ping -c 2 192.168.10.13  # DNS externe

echo ""
echo "========================================="
echo " Serveur MAIL configuré avec succès !"
echo " IP DMZ : 192.168.10.11/24"
echo " Passerelle DMZ : 192.168.10.254"
echo " SMTP : port 25"
echo " IMAP : port 143"
echo " Accessible depuis le LAN/DMZ"
echo "========================================="
