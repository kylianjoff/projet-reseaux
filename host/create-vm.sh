# Création d'une ISO à partir d'un dossier (nécessite genisoimage ou mkisofs)
function create_iso_from_folder() {
    local src_folder="$1"
    local iso_path="$2"
    local volume_name="SCRIPTS"
    if ! command -v genisoimage >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1; then
        echo "Erreur : genisoimage ou mkisofs requis pour créer une ISO." >&2
        exit 1
    fi
    local iso_tool
    if command -v genisoimage >/dev/null 2>&1; then
        iso_tool=genisoimage
    else
        iso_tool=mkisofs
    fi
    "$iso_tool" -o "$iso_path" -V "$volume_name" -J -R "$src_folder"
}
# Génération du fichier preseed avec scripts invités
function generate_preseed() {
    local file_path="$1"
    local admin_user="$2"
    local admin_password="$3"
    local root_password="$4"
    local hostname="$5"
    local install_gnome="$6"
    shift 6
    local script_files=("$@")

    local script_commands="in-target /bin/sh -c \"mkdir -p /home/${admin_user} /opt/projet-reseaux/guest\""
    for script in "${script_files[@]}"; do
        if [[ -f "$GUEST_SCRIPTS/$script" ]]; then
            local content=$(awk '{printf "%s\\n", $0}' "$GUEST_SCRIPTS/$script" | base64 -w0)
            script_commands+="; in-target /bin/sh -c \"printf %s $content | base64 -d > /home/${admin_user}/${script}; chmod +x /home/${admin_user}/${script}\""
            script_commands+="; in-target /bin/sh -c \"printf %s $content | base64 -d > /opt/projet-reseaux/guest/${script}; chmod +x /opt/projet-reseaux/guest/${script}\""
        fi
    done
    script_commands+="; in-target /bin/sh -c \"chown -R ${admin_user}:${admin_user} /home/${admin_user}\""

    local tasksel_lines=""
    if [[ "$install_gnome" == "1" ]]; then
        tasksel_lines="tasksel tasksel/first multiselect standard, gnome-desktop\nd-i pkgsel/run_tasksel boolean true"
    else
        tasksel_lines="d-i pkgsel/run_tasksel boolean false"
    fi

    cat > "$file_path" <<EOF
d-i debian-installer/locale string fr_FR.UTF-8
d-i debian-installer/language string fr
d-i debian-installer/country string FR
d-i debconf/priority string critical
d-i preseed/interactive boolean false

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/use_mirror boolean true
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/cdrom/set-next boolean false
d-i apt-setup/disable-cdrom-entries boolean true
d-i localechooser/supported-locales multiselect fr_FR.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select fr
d-i keyboard-configuration/layoutcode string fr
d-i keyboard-configuration/variantcode string oss

d-i netcfg/choose_interface select enp0s8
d-i netcfg/get_hostname string $hostname
d-i netcfg/get_domain string local

d-i passwd/root-login boolean true
d-i passwd/root-password password $root_password
d-i passwd/root-password-again password $root_password
d-i passwd/make-user boolean true
d-i passwd/user-fullname string $admin_user
d-i passwd/username string $admin_user
d-i passwd/user-password password $admin_password
d-i passwd/user-password-again password $admin_password

d-i clock-setup/utc boolean true
d-i time/zone string Europe/Paris

d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

$tasksel_lines
d-i pkgsel/include string
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string default

d-i preseed/late_command string \
$script_commands

d-i finish-install/reboot_in_progress note
EOF
}
#!/bin/bash
set -euo pipefail

# Dépendances : VBoxManage (VirtualBox), dialog (optionnel pour UI)

# Fonctions utilitaires
function ask() {
    local prompt="$1" default="$2" var
    read -rp "$prompt [$default] : " var
    echo "${var:-$default}"
}


# Paramètres par défaut
ADMIN_USER="administrateur"
ADMIN_PASSWORD="admin"
ROOT_PASSWORD="root"
UNATTENDED=1
ISO_PATH=""
OVA_PATH=""

# Analyse des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --iso)
            ISO_PATH="$2"; shift 2;;
        --ova)
            OVA_PATH="$2"; shift 2;;
        --admin-user)
            ADMIN_USER="$2"; shift 2;;
        --admin-password)
            ADMIN_PASSWORD="$2"; shift 2;;
        --root-password)
            ROOT_PASSWORD="$2"; shift 2;;
        --no-unattended)
            UNATTENDED=0; shift;;
        *)
            echo "Argument inconnu: $1"; exit 1;;
    esac
done

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
    # Préparation scripts invités
    script_files=("common.sh")
    if [[ "$VM_TYPE" == "Serveur" ]]; then
        script_files+=("server-$SERVER_ROLE.sh")
    else
        script_files+=("client.sh")
    fi
    install_gnome=0
    [[ "$VM_TYPE" == "Client" ]] && install_gnome=1

    # Génération du preseed
    generate_preseed "$PRESEED_PATH" "$ADMIN_USER" "$ADMIN_PASSWORD" "$ROOT_PASSWORD" "$VM_NAME" "$install_gnome" "${script_files[@]}"

    "$VBOXMANAGE_PATH" createvm --name "$VM_NAME" --ostype Debian_64 --register
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --memory $MEMORY --cpus $CPUS --vram $VRAM
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic1 intnet --intnet1 "$INTNET_NAME" --nictype1 82540EM --cableconnected1 off
    "$VBOXMANAGE_PATH" modifyvm "$VM_NAME" --nic2 nat --nictype2 82540EM --cableconnected2 on
    "$VBOXMANAGE_PATH" storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
    DISK_PATH="$VDI_DIR/$VM_NAME.vdi"
    "$VBOXMANAGE_PATH" createhd --filename "$DISK_PATH" --size $DISK --variant Standard
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 0 --type hdd --medium "$DISK_PATH"
    "$VBOXMANAGE_PATH" storageattach "$VM_NAME" --storagectl "SATA" --port 1 --type dvddrive --medium "$ISO_PATH"

    # Installation automatisée (unattended)
    if [[ "$UNATTENDED" == "1" ]]; then
        if "$VBOXMANAGE_PATH" unattended install --help >/dev/null 2>&1; then
            "$VBOXMANAGE_PATH" unattended install "$VM_NAME" \
                --iso="$ISO_PATH" \
                --script-template="$PRESEED_PATH" \
                --user="$ADMIN_USER" \
                --user-password="$ADMIN_PASSWORD" \
                --admin-password="$ROOT_PASSWORD" \
                --full-user-name="$ADMIN_USER" \
                --hostname="$VM_NAME.local" \
                --locale="fr_FR" \
                --time-zone="Europe/Paris" \
                --country="FR" \
                --language="fr" \
                --package-selection-adjustment=minimal \
                --start-vm=headless
            "$VBOXMANAGE_PATH" controlvm "$VM_NAME" setlinkstate1 on || echo "Impossible d'activer la carte réseau 1 après installation."
        else
            echo "VBoxManage unattended non supporté. Lancez l'installation manuellement."
            "$VBOXMANAGE_PATH" startvm "$VM_NAME" --type headless
        fi
    else
        "$VBOXMANAGE_PATH" startvm "$VM_NAME" --type headless
    fi
fi

echo "VM '$VM_NAME' prête. Réseau: NAT + intnet '$INTNET_NAME'."
