param(
    [string]$IsoPath,
    [string]$OvaPath,
    [string]$AdminUser = "administrateur",
    [string]$AdminPassword = "admin",
    [string]$RootPassword = "root",
    [switch]$Unattended
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Fonctions Utilitaires ---
function Get-VBoxManagePath {
    $defaultPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $defaultPath) { return $defaultPath }
    $fromEnv = $env:VBOX_MSI_INSTALL_PATH
    if ($fromEnv) {
        $candidate = Join-Path $fromEnv "VBoxManage.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Read-Choice {
    param([string]$Prompt, [string[]]$ValidValues)
    while ($true) {
        $value = Read-Host $Prompt
        if ($ValidValues -contains $value) { return $value }
        Write-Host "Choix invalide. Valeurs autorisées: $($ValidValues -join ', ')"
    }
}

# --- Initialisation des Chemins ---
$VBoxManage = Get-VBoxManagePath
if (-not $VBoxManage) { 
    Write-Error "VirtualBox non trouvé. Installez VirtualBox ou définissez VBOX_MSI_INSTALL_PATH."
    exit 1 
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$guestScriptsPath = Join-Path $projectRoot "guest"
$defaultIso = Join-Path $projectRoot "iso\debian-13.iso"
$preseedPath = Join-Path $projectRoot "cloud-init\preseed\preseed.cfg"
$diskRoot = Join-Path $projectRoot "vdi"

if (-not (Test-Path $diskRoot)) { New-Item -Path $diskRoot -ItemType Directory | Out-Null }

# --- Menus de Sélection ---
Write-Host "1) Client`n2) Serveur`n3) Pare-feu (OVA)"
$vmTypeChoice = Read-Choice "Choix" @("1", "2", "3")

$serverRole = $null
if ($vmTypeChoice -eq "2") {
    Write-Host "1) WEB`n2) DNS`n3) DHCP`n4) MAIL`n5) VPN`n6) BDD`n7) SYSLOG`n8) BACKUP`n9) NTP"
    $roleChoice = Read-Choice "Type de serveur" @("1", "2", "3", "4", "5", "6", "7", "8", "9")
    $serverRole = switch ($roleChoice) {
        "1" { "web" }; "2" { "dns" }; "3" { "dhcp" }; "4" { "mail" }; "5" { "vpn" }; "6" { "db" }; "7" { "syslog" }; "8" { "backup" }; "9" { "ntp" }
    }
}

$fwRole = $null
if ($vmTypeChoice -eq "3") {
    Write-Host "1) Pare-feu Externe`n2) Pare-feu Interne"
    $fwChoice = Read-Choice "Type de pare-feu" @("1", "2")
    $fwRole = if ($fwChoice -eq "1") { "external" } else { "internal" }
}

# --- Configuration Réseau ---
if ($vmTypeChoice -eq "3") {
    $intNetName = "DMZ"
    $OvaPath = Join-Path $projectRoot "ova\firewall-$fwRole.ova"
} else {
    Write-Host "1) DMZ (192.168.10.0/24)`n2) LAN (192.168.20.0/24)"
    $netChoice = Read-Choice "Réseau de la VM" @("1", "2")
    $intNetName = if ($netChoice -eq "1") { "DMZ" } else { "LAN" }
}

# --- Nom et Ressources ---
$defaultName = switch ($vmTypeChoice) { "1" { "client" }; "2" { "srv-$serverRole" }; "3" { "firewall-$fwRole" } }
$name = Read-Host "Nom de la VM (Entrée = $defaultName)"
$name = if ($name) { $name } else { $defaultName }

$memory = if ($vmTypeChoice -eq "1") { 4096 } else { 1024 }
$diskSizeMb = if ($serverRole -eq "backup") { 51200 } else { 10240 }

# --- LOGIQUE DE L'ISO (Version Initiale) ---
if ($vmTypeChoice -ne "3") {
    if (-not $IsoPath) {
        if (Test-Path $defaultIso) {
            $IsoPath = $defaultIso
        } else {
            $IsoPath = Read-Host "Chemin vers l'ISO Debian"
        }
    }

    if (-not (Test-Path $IsoPath)) {
        Write-Error "ISO introuvable: $IsoPath"
        exit 1
    }
}

# --- Création de la VM ---
if ($vmTypeChoice -eq "3") {
    & $VBoxManage import $OvaPath --vsys 0 --vmname $name
    if ($fwRole -eq "external") {
        & $VBoxManage modifyvm $name --nic1 nat --nic2 intnet --intnet2 DMZ
    } else {
        & $VBoxManage modifyvm $name --nic1 intnet --intnet1 LAN --nic2 intnet --intnet2 DMZ
    }
} else {
    & $VBoxManage createvm --name $name --ostype Debian_64 --register
    & $VBoxManage modifyvm $name --memory $memory --vram 128 --nic1 intnet --intnet1 $intNetName --nic2 nat

    & $VBoxManage storagectl $name --name "SATA" --add sata --controller IntelAhci
    $diskPath = Join-Path $diskRoot "$name.vdi"
    & $VBoxManage createhd --filename $diskPath --size $diskSizeMb
    & $VBoxManage storageattach $name --storagectl "SATA" --port 0 --type hdd --medium $diskPath
    & $VBoxManage storageattach $name --storagectl "SATA" --port 1 --type dvddrive --medium $IsoPath

    # Installation automatique
    & $VBoxManage unattended install $name --iso $IsoPath --script-template $preseedPath --user $AdminUser --user-password $AdminPassword --admin-password $RootPassword --start-vm headless
}

Write-Host "VM '$name' prête. Réseau: NAT + intnet '$intNetName'."