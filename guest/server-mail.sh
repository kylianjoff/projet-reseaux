#!/bin/bash

echo "========================================="
echo " Configuration du SERVEUR MAIL (Postfix)"
echo "========================================="
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en root."
  exit 1
fi

echo "[0/6] Préconfiguration de Postfix pour installation non interactive"
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string mail.projet.local" | debconf-set-selections

echo "[1/6] Mise à jour des paquets"
apt update -y

echo "[2/6] Installation des paquets mail"
DEBIAN_FRONTEND=noninteractive apt install -y postfix dovecot-core mailutils

echo "[3/6] Configuration de Postfix"
postconf -e "myhostname = mail.projet.local"
postconf -e "mydomain = projet.local"
postconf -e "myorigin = /etc/mailname"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "mynetworks = 127.0.0.0/8 192.168.20.0/24"

echo "[4/6] Configuration de Dovecot (IMAP)"
# Activation Maildir
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
# Autoriser l'authentification en clair (réseau local)
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
# Vérification du port IMAP
sed -i 's/^#port = 143/port = 143/' /etc/dovecot/conf.d/10-master.conf

echo "[5/6] Création du Maildir pour l'utilisateur administrateur"
if [ -d /home/administrateur ]; then
  maildirmake.dovecot /home/administrateur/Maildir
  chown -R administrateur:administrateur /home/administrateur/Maildir
fi

echo "[6/6] Démarrage des services mail"
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

echo ""
echo "========================================="
echo " Serveur MAIL configuré avec succès"
echo " SMTP : port 25"
echo " IMAP : port 143"
echo "========================================="
echo "Done my MED"
