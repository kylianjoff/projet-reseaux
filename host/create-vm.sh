#!/bin/bash
set -euo pipefail

# Dépendances : VBoxManage (VirtualBox), dialog (optionnel pour UI)

# Fonctions utilitaires
function ask() {
    local prompt="$1" default="$2" var
    read -rp "$prompt [$default] : " var
    echo "${var:-$default}"
}

# Chemins par défaut
PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
GUEST_SCRIPTS="$PROJECT_ROOT/guest"
ISO_DIR="$PROJECT_ROOT/iso"
OVA_DIR="$PROJECT_ROOT/ova"
VDI_DIR="$PROJECT_ROOT/vdi"
PRESEED_DIR="$PROJECT_ROOT/cloud-init/preseed"
PRESEED_PATH="$PRESEED_DIR/preseed.cfg"

mkdir -p "$VDI_DIR" "$PRESEED_DIR"

# Choix du type de VM
PS3="Type de VM : "
select VM_TYPE in "Client" "Serveur" "Pare-feu (OVA)"; do
    [[ -n "$VM_TYPE" ]] && break
    echo "Choix invalide."
done

# Rôle serveur
if [[ "$VM_TYPE" == "Serveur" ]]; then
    PS3="Type de serveur : "
    select SERVER_ROLE in "web" "dns" "dhcp" "mail" "vpn" "db"; do
        [[ -n "$SERVER_ROLE" ]] && break
        echo "Choix invalide."
    done
fi

# Rôle pare-feu
if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    PS3="Type de pare-feu : "
    select FW_ROLE in "external" "internal"; do
        [[ -n "$FW_ROLE" ]] && break
        echo "Choix invalide."
    done
fi

# Choix réseau
if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    INTNET_NAME="DMZ"
    if [[ "$FW_ROLE" == "external" ]]; then
        OVA_FILE="$OVA_DIR/firewall-externe.ova"
    else
        OVA_FILE="$OVA_DIR/firewall-interne.ova"
    fi
else
    PS3="Réseau de la VM : "
    select NET_CHOICE in "DMZ (192.168.10.0/24)" "LAN (192.168.20.0/24)"; do
        [[ -n "$NET_CHOICE" ]] && break
        echo "Choix invalide."
    done
    INTNET_NAME=$( [[ "$NET_CHOICE" == DMZ* ]] && echo "DMZ" || echo "LAN" )
fi


# Nom de la VM avec gestion de nom unique
case "$VM_TYPE" in
    "Client") DEFAULT_NAME="client" ;;
    "Serveur") DEFAULT_NAME="srv-$SERVER_ROLE" ;;
    "Pare-feu (OVA)") DEFAULT_NAME="firewall-$FW_ROLE" ;;
esac

function get_unique_vm_name() {
    local base_name="$1"
    local name="$base_name"
    local i=1
    while "$VBOXMANAGE_PATH" list vms | grep -q '"'"$name"'"'; do
        name="${base_name}-$i"
        i=$((i+1))
    done
    echo "$name"
}

read -rp "Nom de la VM [${DEFAULT_NAME}] : " VM_NAME
VM_NAME="${VM_NAME:-$DEFAULT_NAME}"
UNIQUE_VM_NAME=$(get_unique_vm_name "$VM_NAME")
if [[ "$UNIQUE_VM_NAME" != "$VM_NAME" ]]; then
    echo "Nom déjà utilisé. Nouveau nom: $UNIQUE_VM_NAME"
    VM_NAME="$UNIQUE_VM_NAME"
fi

# Mémoire, disque, CPU
case "$VM_TYPE" in
    "Client") MEMORY=4096 ; DISK=20480 ; VRAM=128 ;;
    "Serveur") MEMORY=1024 ; DISK=10240 ; VRAM=64 ;;
    "Pare-feu (OVA)") MEMORY=1024 ; DISK=10240 ; VRAM=64 ;;
esac
CPUS=1

# ISO/OVA
if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    if [[ ! -f "$OVA_FILE" ]]; then echo "OVA introuvable: $OVA_FILE"; exit 1; fi
else
    ISO_PATH=$(ask "Chemin ISO Debian" "$ISO_DIR/debian-13.iso")
    if [[ ! -f "$ISO_PATH" ]]; then echo "ISO introuvable: $ISO_PATH"; exit 1; fi
fi


# Détection automatique de VBoxManage (VirtualBox)
function find_vboxmanage() {
    # 1. Si VBoxManage est dans le PATH
    if command -v VBoxManage >/dev/null 2>&1; then
        command -v VBoxManage
        return 0
    fi
    # 2. Emplacement standard Windows (pour WSL ou Git Bash)
    for d in "/mnt/c/Program Files/Oracle/VirtualBox" "/c/Program Files/Oracle/VirtualBox"; do
        if [ -x "$d/VBoxManage.exe" ]; then
            echo "$d/VBoxManage.exe"
            return 0
        fi
    done
    # 3. Variable d'environnement VBOX_MSI_INSTALL_PATH (pour WSL)
    if [ -n "${VBOX_MSI_INSTALL_PATH:-}" ] && [ -x "${VBOX_MSI_INSTALL_PATH}/VBoxManage.exe" ]; then
        echo "${VBOX_MSI_INSTALL_PATH}/VBoxManage.exe"
        return 0
    fi
    return 1
}

VBOXMANAGE_PATH=$(find_vboxmanage) || { echo "VBoxManage (VirtualBox) non trouvé. Installez VirtualBox ou ajoutez VBoxManage au PATH."; exit 1; }
echo "VBoxManage trouvé : $VBOXMANAGE_PATH"


# Création de la VM


# (Plus besoin de ce test, la fonction get_unique_vm_name gère le nom unique)


if [[ "$VM_TYPE" == "Pare-feu (OVA)" ]]; then
    "$VBOXMANAGE_PATH" import "$OVA_FILE" --vsys 0 --vmname "$VM_NAME"
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --memory $MEMORY --cpus $CPUS --vram $VRAM
    if [[ "$FW_ROLE" == "external" ]]; then
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 nat --nictype1 82540EM --cableconnected1 on
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic2 intnet --intnet2 DMZ --nictype2 82540EM --cableconnected2 on
    else
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 intnet --intnet1 LAN --nictype1 82540EM --cableconnected1 on
        "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic2 intnet --intnet2 DMZ --nictype2 82540EM --cableconnected2 on
    fi
else
    "$VBOXMANAGE_PATH" createvm --name "$VM_NAME" --ostype Debian_64 --register
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --memory $MEMORY --cpus $CPUS --vram $VRAM
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 intnet --intnet1 "$INTNET_NAME" --nictype1 82540EM --cableconnected1 off
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic2 nat --nictype2 82540EM --cableconnected2 on
    "$VBOXMANAGE_PATH" storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
    DISK_PATH="$VDI_DIR/$VM_NAME.vdi"
    "$VBOXMANAGE_PATH" createhd --filename "$DISK_PATH" --size $DISK --variant Standard
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 0 --type hdd --medium "$DISK_PATH"
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 1 --type dvddrive --medium "$ISO_PATH"
    # Démarrage en mode headless
    "$VBOXMANAGE_PATH" startvm "$VM_NAME" --type headless
fi

echo "VM '$VM_NAME' prête. Réseau: NAT + intnet '$INTNET_NAME'."
