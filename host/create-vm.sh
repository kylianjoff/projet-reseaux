#!/bin/bash
set -euo pipefail

# ==============================================================================
# SCRIPT DE CRÉATION DE VM - ARCHITECTURE RÉSEAU (DMZ/LAN)
# Version : 2.0 (Ajout Syslog, Backup, NTP)
# ==============================================================================

# --- FONCTIONS UTILITAIRES ---

function find_vboxmanage() {
    if command -v VBoxManage >/dev/null 2>&1; then
        command -v VBoxManage
        return 0
    fi
    for d in "/mnt/c/Program Files/Oracle/VirtualBox" "/c/Program Files/Oracle/VirtualBox"; do
        if [ -x "$d/VBoxManage.exe" ]; then
            echo "$d/VBoxManage.exe"
            return 0
        fi
    done
    return 1
}

function check_vm_locked() {
    local vm_name="$1"
    if "$VBOXMANAGE_PATH" list vms | grep -q '"'"$vm_name"'"'; then
        if "$VBOXMANAGE_PATH" showvminfo "$vm_name" --machinereadable | grep -q 'VMState="locked"'; then
            echo "[ERREUR] La VM $vm_name est verrouillée. Fermez VirtualBox." >&2
            exit 1
        fi
    fi
}

function remove_existing_vm() {
    local vm_name="$1"
    local basefolder="$2"
    if "$VBOXMANAGE_PATH" list vms | grep -q '"'"$vm_name"'"'; then
        echo "[DEBUG] Suppression de la VM existante : $vm_name"
        "$VBOXMANAGE_PATH" unregistervm "$vm_name" --delete || true
    fi
    [ -d "$basefolder/$vm_name" ] && rm -rf "$basefolder/$vm_name"
}

function ask() {
    local prompt="$1" default="$2" var
    read -rp "$prompt [$default] : " var
    echo "${var:-$default}"
}

# --- INITIALISATION ET DÉTECTION ---

VBOXMANAGE_PATH=$(find_vboxmanage) || { echo "VBoxManage non trouvé."; exit 1; }
PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
GUEST_SCRIPTS="$PROJECT_ROOT/guest"
ISO_DIR="$PROJECT_ROOT/iso"
VDI_DIR="$PROJECT_ROOT/vdi"
PRESEED_DIR="$PROJECT_ROOT/cloud-init/preseed"
PRESEED_PATH="$PRESEED_DIR/preseed.cfg"
VM_BASEFOLDER="$HOME/VirtualBox VMs"

mkdir -p "$VDI_DIR" "$PRESEED_DIR" "$VM_BASEFOLDER"

# --- MENUS DE SÉLECTION ---

PS3="Type de VM : "
select VM_TYPE in "Client" "Serveur" "Pare-feu (OVA)"; do
    [[ -n "$VM_TYPE" ]] && break
done

if [[ "$VM_TYPE" == "Serveur" ]]; then
    PS3="Rôle du serveur : "
    # Ajout des nouveaux rôles Syslog, Backup et NTP
    select SERVER_ROLE in "web" "dns" "dhcp" "mail" "vpn" "db" "syslog" "backup" "ntp"; do
        [[ -n "$SERVER_ROLE" ]] && break
    done
fi

if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    PS3="Type de pare-feu : "
    select FW_ROLE in "external" "internal"; do
        [[ -n "$FW_ROLE" ]] && break
    done
    INTNET_NAME="DMZ"
    OVA_FILE="$PROJECT_ROOT/ova/firewall-$FW_ROLE.ova"
else
    PS3="Réseau cible : "
    select NET_CHOICE in "DMZ (192.168.10.0/24)" "LAN (192.168.20.0/24)"; do
        [[ -n "$NET_CHOICE" ]] && break
    done
    INTNET_NAME=$( [[ "$NET_CHOICE" == DMZ* ]] && echo "DMZ" || echo "LAN" )
fi

# --- CONFIGURATION DES RESSOURCES ---

case "$VM_TYPE" in
    "Client") DEFAULT_NAME="client" ; MEMORY=4096 ; DISK=20480 ; VRAM=256 ;;
    "Serveur") 
        DEFAULT_NAME="srv-$SERVER_ROLE" ; MEMORY=1024 ; DISK=10240 ; VRAM=128
        # Ajustement spécifique pour le serveur de Backup (besoin de stockage)
        if [[ "$SERVER_ROLE" == "backup" ]]; then DISK=51200 ; fi 
        ;;
    "Pare-feu (OVA)") DEFAULT_NAME="firewall-$FW_ROLE" ; MEMORY=1024 ; DISK=10240 ; VRAM=128 ;;
esac

read -rp "Nom de la VM [${DEFAULT_NAME}] : " VM_NAME
VM_NAME="${VM_NAME:-$DEFAULT_NAME}"
ISO_PATH=$(ask "Chemin ISO Debian" "$ISO_DIR/debian-13.iso")

# --- CRÉATION / IMPORT ---

check_vm_locked "$VM_NAME"
remove_existing_vm "$VM_NAME" "$VM_BASEFOLDER"

if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    "$VBOXMANAGE_PATH" import "$OVA_FILE" --vsys 0 --vmname "$VM_NAME"
    # Configuration des cartes réseaux spécifiques aux Firewalls (NAT + INTNET)
    if [[ "$FW_ROLE" == "external" ]]; then
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 nat --nic2 intnet --intnet2 DMZ
    else
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 intnet --intnet1 LAN --nic2 intnet --intnet2 DMZ
    fi
else
    # Préparation des scripts de post-installation
    script_files=("common.sh" "server-$SERVER_ROLE.sh")
    [[ "$VM_TYPE" == "Client" ]] && script_files=("common.sh" "client.sh")

    # Utilisation de ta fonction generate_preseed existante (non répétée ici pour la lisibilité)
    # generate_preseed "$PRESEED_PATH" ... "${script_files[@]}"

    "$VBOXMANAGE_PATH" createvm --name "$VM_NAME" --ostype Debian_64 --basefolder "$VM_BASEFOLDER" --register
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --memory $MEMORY --vram $VRAM --nic1 intnet --intnet1 "$INTNET_NAME" --nic2 nat

    # Stockage
    "$VBOXMANAGE_PATH" storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
    DISK_PATH="$VDI_DIR/$VM_NAME.vdi"
    "$VBOXMANAGE_PATH" createhd --filename "$DISK_PATH" --size $DISK --variant Standard
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$DISK_PATH"
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"
    
    # Lancement Unattended (Installation automatique)
    "$VBOXMANAGE_PATH" unattended install "$VM_NAME" --iso="$ISO_PATH" --script-template="$PRESEED_PATH" --start-vm=headless
fi

echo "VM '$VM_NAME' créée avec succès dans le réseau '$INTNET_NAME'."