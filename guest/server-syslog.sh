#!/bin/bash
# Configuration du serveur Syslog centralisé (srv-syslog) - 192.168.20.15

if [ "${EUID}" -ne 0 ]; then
    echo "ERREUR : Lancez avec sudo"
    exit 1
fi

echo "== Configuration Réseau (IP Statique) =="

# Désactiver NetworkManager temporairement s'il est présent
systemctl stop NetworkManager 2>/dev/null
systemctl disable NetworkManager 2>/dev/null

# Configurer les interfaces réseau
cat > /etc/network/interfaces <<EOF
# Interface loopback
auto lo
iface lo inet loopback

# Interface LAN (192.168.20.0/24) - enp0s3
auto enp0s3
iface enp0s3 inet static
    address 192.168.20.15
    netmask 255.255.255.0
    gateway 192.168.20.254

# Interface NAT (internet) - enp0s8 (DHCP sans route par défaut)
auto enp0s8
iface enp0s8 inet dhcp
    # Supprimer la route par défaut qui pourrait être ajoutée par DHCP
    post-up ip route del default via 10.0.3.2 dev enp0s8 2>/dev/null || true
    # Ne pas ajouter de route par défaut
    up route del default dev enp0s8 2>/dev/null || true
EOF

echo "== Redémarrage du réseau =="
# Remonter les interfaces
ip addr flush dev enp0s3 2>/dev/null
ip addr flush dev enp0s8 2>/dev/null
systemctl restart networking

# Vérifier et supprimer les routes par défaut superflues
echo "== Nettoyage des routes =="
# Supprimer toute route par défaut qui ne passe pas par 192.168.20.254
while ip route show default | grep -v "192.168.20.254" > /dev/null; do
    BAD_ROUTE=$(ip route show default | grep -v "192.168.20.254" | head -1)
    ip route del $BAD_ROUTE 2>/dev/null
done

# S'assurer que la bonne route par défaut existe
if ! ip route show default | grep -q "192.168.20.254"; then
    ip route add default via 192.168.20.254 dev enp0s3
fi

echo "== Installation et Configuration de Rsyslog =="
apt-get update && apt-get install -y rsyslog

# Activer la réception des logs via UDP (port 514)
sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

# Créer un répertoire pour stocker les logs des machines distantes
mkdir -p /var/log/remote
chown syslog:adm /var/log/remote

# Configurer rsyslog pour trier les logs par nom de machine
cat > /etc/rsyslog.d/central.conf <<EOF
# Template pour logs distants triés par nom de machine et programme
\$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"

# Rediriger tous les logs vers les templates distants
*.* ?RemoteLogs

# Ne pas écrire les logs distants dans les fichiers locaux
& ~
EOF

echo "== Redémarrage des services =="
systemctl restart rsyslog

# Vérifications
echo "== VÉRIFICATIONS =="
echo ""
echo "1. Configuration réseau :"
ip addr show enp0s3 | grep "inet " || echo "❌ enp0s3 non configurée"
ip addr show enp0s8 | grep "inet " || echo "⚠ enp0s8 peut être sans IP"

echo ""
echo "2. Routes :"
ip route show
echo ""
echo "   ✓ La route par défaut doit être via 192.168.20.254"

echo ""
echo "3. Test connectivité LAN :"
if ping -c 2 192.168.20.254 &>/dev/null; then
    echo "   ✅ Ping vers firewall interne (192.168.20.254) OK"
else
    echo "   ❌ Ping vers firewall interne échoué"
fi

echo ""
echo "4. Service rsyslog :"
if systemctl is-active --quiet rsyslog; then
    echo "   ✅ rsyslog est actif"
else
    echo "   ❌ rsyslog n'est pas actif"
    systemctl status rsyslog --no-pager | head -5
fi

echo ""
echo "5. Port UDP 514 :"
if ss -ulpn | grep -q 514; then
    echo "   ✅ rsyslog écoute sur le port 514 (UDP)"
else
    echo "   ❌ rsyslog n'écoute pas sur le port 514"
fi

echo ""
echo "6. Test local logger :"
TEST_MSG="TEST-SYSLOG-$(date +%s)"
logger "$TEST_MSG"
sleep 1
if cat /var/log/syslog | grep -q "$TEST_MSG"; then
    echo "   ✅ logger fonctionne (message trouvé dans syslog)"
else
    echo "   ❌ logger ne fonctionne pas"
    echo "      Vérifiez /var/log/syslog:"
    ls -la /var/log/syslog
fi

echo ""
echo "== Serveur Syslog prêt sur 192.168.20.15 =="
echo "   - Interface LAN: enp0s3 (192.168.20.15/24)"
echo "   - Interface NAT: enp0s8 (DHCP, sans route par défaut)"
echo "   - Port UDP 514 ouvert pour réception des logs distants"
echo "   - Logs distants: /var/log/remote/"
echo ""
echo "== Fait par MED =="