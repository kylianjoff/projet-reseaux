#!/bin/bash
set -euo pipefail

echo "== Configuration du Serveur NTP (Chrony) =="
apt-get update && apt-get install -y chrony

# Autoriser les réseaux de ton architecture à interroger ce serveur
# Selon ton plan : DMZ (192.168.10.0/24) et LAN (192.168.20.0/24)
cat >> /etc/chrony/chrony.conf <<EOF
allow 192.168.10.0/24
allow 192.168.20.0/24
EOF

systemctl restart chrony
echo "== Serveur NTP opérationnel =="