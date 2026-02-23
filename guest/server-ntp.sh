#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_root

echo "================================="
echo " [1/6] Recherche de mises à jour "
echo "================================="
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
    echo "Mise à jour échouée, tentative avec --allow-releaseinfo-change..."
    apt-get update -y --allow-releaseinfo-change
fi

echo "============================================"
echo " [2/6] Installation des paquets nécessaires "
echo "============================================"
# Installation de base + usermod fait partie du package passwd
apt-get install -y \
    sudo \
    curl \
    nano \
    vim \
    traceroute \
    iputils-ping \
    ca-certificates \
    net-tools \
    iproute2 \
    ifupdown \
    chrony \
    whiptail \
    passwd \
    login

# Vérifier que usermod est disponible
if ! command -v usermod &> /dev/null; then
    echo "ERREUR: usermod n'est pas disponible même après installation de passwd"
    echo "Recherche de usermod..."
    find / -name usermod 2>/dev/null || echo "usermod introuvable"
    exit 1
fi

ensure_whiptail

echo "============================================"
echo " [3/6] Configuration utilisateur "
echo "============================================"
DEFAULT_USER="administrateur"

# Saisie du nom d'utilisateur avec whiptail
USER=$(ui_input "[3/6] Réglage utilisateur" "Nom de l'utilisateur administrateur" "$DEFAULT_USER") || exit 1

# Vérifier si l'utilisateur existe
if id "$USER" >/dev/null 2>&1; then
    echo "Ajout de l'utilisateur $USER au groupe sudo..."
    # Utilisation du chemin absolu pour usermod
    /usr/sbin/usermod -aG sudo "$USER" || {
        echo "Erreur lors de l'ajout au groupe sudo, tentative avec chemin relatif..."
        usermod -aG sudo "$USER"
    }
else
    echo "ATTENTION: Utilisateur '$USER' introuvable, création en cours..."
    # Créer l'utilisateur s'il n'existe pas
    /usr/sbin/useradd -m -s /bin/bash -G sudo "$USER" || {
        echo "Erreur lors de la création de l'utilisateur, tentative avec useradd simple..."
        useradd -m -s /bin/bash "$USER" && /usr/sbin/usermod -aG sudo "$USER"
    }
    echo "Définissez le mot de passe pour $USER avec: passwd $USER"
fi

echo "============================================"
echo " [4/6] Configuration réseau "
echo "============================================"
DEFAULT_IFACE="enp0s3"

IFACE=$(ui_input "[4/6] Interface" "Nom de l'interface réseau" "$DEFAULT_IFACE") || exit 1
SERVER_IP=$(ui_input "[4/6] Adresse IP" "Adresse IP du serveur NTP" "192.168.20.13") || exit 1
NETMASK=$(ui_input "[4/6] Masque" "Masque réseau" "255.255.255.0") || exit 1
GATEWAY=$(ui_input "[4/6] Passerelle" "Passerelle par défaut" "192.168.20.254") || exit 1

# Configuration du fichier interfaces
ui_info "[4/6] Configuration réseau" "Configuration IP statique"
if [ -f /etc/network/interfaces ]; then
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s)
fi

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${SERVER_IP}
    netmask ${NETMASK}
    gateway ${GATEWAY}
EOF

echo "============================================"
echo " [5/6] Configuration du serveur NTP (chrony) "
echo "============================================"
ui_info "[5/6] Configuration NTP" "Chrony - serveur de temps"

# Sauvegarde de la configuration existante
if [ -f /etc/chrony/chrony.conf ]; then
    cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak.$(date +%s)
fi

# Configuration des serveurs NTP amont (pool.ntp.org)
cat > /etc/chrony/chrony.conf <<EOF
# Serveurs NTP publics (pool)
pool 0.fr.pool.ntp.org iburst
pool 1.fr.pool.ntp.org iburst
pool 2.fr.pool.ntp.org iburst
pool 3.fr.pool.ntp.org iburst

# Autoriser l'ajustement rapide de l'horloge
makestep 1 3

# Enregistrer la dérive de l'horloge entre les redémarrages
driftfile /var/lib/chrony/drift

# Autoriser les clients du réseau local à interroger ce serveur
allow 192.168.20.0/24   # LAN
allow 192.168.10.0/24   # DMZ (optionnel, si besoin)

# Désactiver l'accès depuis Internet (par défaut chrony écoute sur toutes les interfaces)
bindaddress ${SERVER_IP}
bindcmdaddress ${SERVER_IP}

# Activer les statistiques
logdir /var/log/chrony
log measurements statistics tracking
EOF

# Création du fichier de configuration pour les clients (optionnel)
cat > /etc/chrony/chrony.allowed <<EOF
# Réseaux autorisés à interroger le serveur NTP
192.168.20.0/24
192.168.10.0/24
EOF

echo "============================================"
echo " [6/6] Activation et démarrage des services "
echo "============================================"
ui_info "[6/6] Services" "Redémarrage des services réseau et chrony"

# Redémarrer networking
if systemctl list-unit-files | grep -q networking; then
    systemctl restart networking
else
    systemctl restart ifupdown
fi

# Activer et démarrer chrony
systemctl enable chrony
systemctl restart chrony

# Attendre que chrony soit synchronisé
sleep 2

echo ""
echo "============================================"
echo " Vérification de la synchronisation NTP "
echo "============================================"
chronyc tracking || echo "Chrony pas encore synchronisé, patientez quelques minutes."
chronyc sources -v

echo ""
ui_msg "Terminé" "Serveur NTP configuré sur ${SERVER_IP}\nCommande de test: chronyc tracking\nVérification client: chronyc sources"

if whiptail --title "Redémarrage" --yesno "Voulez-vous redémarrer le serveur maintenant ?" 10 70; then
    reboot now
fi