#!/bin/bash
set -euo pipefail

echo "== Configuration du Serveur Syslog (Rsyslog) =="
apt-get update && apt-get install -y rsyslog

# Activer la réception UDP sur le port 514
sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

# Créer un modèle pour organiser les logs par hôte
cat >> /etc/rsyslog.d/00-remote.conf <<EOF
\$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& ~
EOF

systemctl restart rsyslog
echo "== Serveur Syslog prêt à recevoir des logs sur UDP/514 =="