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

# ==============================================================================
# 1. DÉFINITION DES FONCTIONS (Indispensable pour éviter l'erreur CommandNotFound)
# ==============================================================================

function Get-VBoxManagePath {
    $defaultPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $defaultPath) { return $defaultPath }
    return $null
}

function Read-Choice {
    param([string]$Prompt, [string[]]$ValidValues)
    while ($true) {
        $value = Read-Host $Prompt
        if ($ValidValues -contains $value) { return $value }
        Write-Host "Choix invalide."
    }
}

function New-PreseedFile {
    param(
        [string]$FilePath,
        [string]$AdminUser,
        [string]$AdminPassword,
        [string]$RootPassword,
        [string]$Hostname,
        [string]$Domain = "local",
        [object[]]$ScriptFiles = @(),
        [bool]$InstallGnome = $false
    )

    $scriptCommands = @()
    $scriptCommands += ('in-target /bin/sh -c "mkdir -p /home/{0} /opt/projet-reseaux/guest"' -f $AdminUser)

    foreach ($script in $ScriptFiles) {
        $fileName = $script.Name
        $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script.Content))
        $scriptCommands += ('in-target /bin/sh -c "printf %s {0} | base64 -d > /home/{1}/{2}; chmod +x /home/{1}/{2}"' -f $base64, $AdminUser, $fileName)
        $scriptCommands += ('in-target /bin/sh -c "printf %s {0} | base64 -d > /opt/projet-reseaux/guest/{1}; chmod +x /opt/projet-reseaux/guest/{1}"' -f $base64, $fileName)
    }

    $scriptCommands += ('in-target /bin/sh -c "chown -R {0}:{0} /home/{0}"' -f $AdminUser)
    $lateCommand = ($scriptCommands -join "; ")

    $content = @"
d-i debian-installer/locale string fr_FR.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select fr
d-i netcfg/choose_interface select enp0s8
d-i netcfg/get_hostname string $Hostname
d-i netcfg/get_domain string $Domain
d-i passwd/root-login boolean true
d-i passwd/root-password password $RootPassword
d-i passwd/root-password-again password $RootPassword
d-i passwd/make-user boolean true
d-i passwd/username string $AdminUser
d-i passwd/user-password password $AdminPassword
d-i passwd/user-password-again password $AdminPassword
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Paris
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_nooverwrite boolean true
d-i grub-installer/only_debian boolean true
d-i preseed/late_command string \
in-target /bin/sh -c "sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT=\"fr\"/' /etc/default/keyboard"; \
$lateCommand
d-i finish-install/reboot_in_progress note
"@
    Set-Content -Path $FilePath -Value $content -Encoding UTF8
}

# ==============================================================================
# 2. INITIALISATION ET LOGIQUE PRINCIPALE
# ==============================================================================

$VBoxManage = Get-VBoxManagePath
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$diskRoot = Join-Path $projectRoot "vdi"
$guestScriptsPath = Join-Path $projectRoot "guest"
$preseedPath = Join-Path $projectRoot "cloud-init\preseed\preseed.cfg"

# Menus...
Write-Host "1) Client`n2) Serveur`n3) Pare-feu (OVA)"
$vmTypeChoice = Read-Choice "Choix" @("1", "2", "3")

if ($vmTypeChoice -eq "2") {
    Write-Host "1) WEB`n2) DNS`n3) DHCP`n4) MAIL`n5) VPN`n6) BDD`n7) SYSLOG`n8) BACKUP`n9) NTP"
    $roleChoice = Read-Choice "Type de serveur" @("1","2","3","4","5","6","7","8","9")
    $serverRole = switch ($roleChoice) { 
        "1"{"web"};"2"{"dns"};"3"{"dhcp"};"4"{"mail"};"5"{"vpn"};"6"{"db"};"7"{"syslog"};"8"{"backup"};"9"{"ntp"} 
    }
}

$netChoice = Read-Choice "Reseau (1:DMZ, 2:LAN)" @("1", "2")
$intNetName = if ($netChoice -eq "1") { "DMZ" } else { "LAN" }

$defaultName = if ($serverRole) { "srv-$serverRole" } else { "client" }
$name = Read-Host "Nom de la VM (Entree = $defaultName)"
$name = if ($name) { $name } else { $defaultName }

# ISO...
$defaultIso = Join-Path $projectRoot "iso\debian-13.iso"
if (-not $IsoPath) {
    if (Test-Path $defaultIso) { $IsoPath = $defaultIso }
    else { $IsoPath = Read-Host "Chemin vers l'ISO Debian" }
}

# --- NETTOYAGE ---
Write-Host "Nettoyage des anciennes traces pour $name..."
$oldErrorPreference = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
& $VBoxManage unregistervm $name --delete
$ErrorActionPreference = $oldErrorPreference

$diskPath = Join-Path $diskRoot "$name.vdi"
if (Test-Path $diskPath) { Remove-Item $diskPath -Force }

# --- CRÉATION ---
$memory = if ($vmTypeChoice -eq "1") { 4096 } else { 1024 }
$diskSize = if ($serverRole -eq "backup") { 51200 } else { 10240 }

& $VBoxManage createvm --name $name --ostype Debian_64 --register
& $VBoxManage modifyvm $name --memory $memory --vram 128 --nic1 intnet --intnet1 $intNetName --nic2 nat
& $VBoxManage storagectl $name --name "SATA" --add sata --controller IntelAhci
& $VBoxManage createhd --filename $diskPath --size $diskSize --variant Standard
& $VBoxManage storageattach $name --storagectl "SATA" --port 0 --type hdd --medium $diskPath
& $VBoxManage storageattach $name --storagectl "SATA" --port 1 --type dvddrive --medium $IsoPath

# --- INJECTION SCRIPTS ET GÉNÉRATION PRESEED ---
$scriptEntries = @()
$scriptsToInject = @("common.sh")
if ($serverRole) { $scriptsToInject += "server-$serverRole.sh" }

foreach ($sf in $scriptsToInject) {
    $sp = Join-Path $guestScriptsPath $sf
    if (Test-Path $sp) {
        $content = (Get-Content $sp -Raw) -replace "`r`n", "`n"
        $scriptEntries += [pscustomobject]@{ Name = $sf; Content = $content }
    }
}

Write-Host "Génération du preseed pour $name..."
New-PreseedFile -FilePath $preseedPath -AdminUser $AdminUser -AdminPassword $AdminPassword -RootPassword $RootPassword -Hostname $name -ScriptFiles $scriptEntries -InstallGnome ($vmTypeChoice -eq "1")

# --- INSTALLATION ---
& $VBoxManage unattended install $name --iso $IsoPath --script-template $preseedPath --user $AdminUser --user-password $AdminPassword --admin-password $RootPassword --start-vm headless

Write-Host "VM '$name' prête."