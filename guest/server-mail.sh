#!/bin/bash

echo "========================================="
echo " Configuration du SERVEUR MAIL (Postfix/Dovecot)"
echo "========================================="

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en root."
  exit 1
fi

echo "[0/7] Préparation pour installation non interactive"
export DEBIAN_FRONTEND=noninteractive

# Pré-configurer Postfix pour éviter les questions
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string mail.projet.local" | debconf-set-selections

echo "[1/7] Mise à jour des paquets"
apt update -y

echo "[2/7] Installation Postfix, Dovecot et mailutils"
apt install -y postfix dovecot-core mailutils

# Vérification que Postfix est installé
if ! command -v postconf &> /dev/null; then
    echo "Erreur : Postfix n'est pas installé correctement."
    exit 1
fi

echo "[3/7] Configuration Postfix"
postconf -e "myhostname = mail.projet.local"
postconf -e "mydomain = projet.local"
postconf -e "myorigin = /etc/mailname"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24 192.168.20.0/24"

echo "[4/7] Configuration Dovecot (IMAP)"
# Maildir
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
# Autoriser auth en clair pour le LAN
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
# Port IMAP
sed -i 's/^#port = 143/port = 143/' /etc/dovecot/conf.d/10-master.conf

echo "[5/7] Création du Maildir pour administrateur"
if [ -d /home/administrateur ]; then
    maildirmake.dovecot /home/administrateur/Maildir
    chown -R administrateur:administrateur /home/administrateur/Maildir
fi

echo "[6/7] Démarrage et activation des services"
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

echo "[7/7] Vérification écoute sur les ports"
ss -tlnp | grep -E ':(25|143)'

echo ""
echo "========================================="
echo " Serveur MAIL configuré avec succès !"
echo " SMTP : port 25"
echo " IMAP : port 143"
echo " Accessible depuis le LAN/DMZ"
echo "========================================="
echo "Done my MED"
