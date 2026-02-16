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

# --- FONCTIONS RÉSEAU ET SYSTÈME ---

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

# --- GESTION DU PRESEED ---

function New-PreseedFile {
    param(
        [string]$FilePath, [string]$AdminUser, [string]$AdminPassword, [string]$RootPassword,
        [string]$Hostname, [string]$Domain = "local", [object[]]$ScriptFiles = @(), [bool]$InstallGnome = $false
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
    $taskselLines = if ($InstallGnome) { "tasksel tasksel/first multiselect standard, gnome-desktop`nd-i pkgsel/run_tasksel boolean true" } else { "d-i pkgsel/run_tasksel boolean false" }

    $content = @"
d-i debian-installer/locale string fr_FR.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select fr
d-i netcfg/choose_interface select enp0s8
d-i netcfg/get_hostname string $Hostname
d-i netcfg/get_domain string $Domain
d-i passwd/root-password password $RootPassword
d-i passwd/root-password-again password $RootPassword
d-i passwd/username string $AdminUser
d-i passwd/user-password password $AdminPassword
d-i passwd/user-password-again password $AdminPassword
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_nooverwrite boolean true
$taskselLines
d-i grub-installer/only_debian boolean true
d-i preseed/late_command string \
in-target /bin/sh -c "sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT=\"fr\"/' /etc/default/keyboard"; \
$lateCommand
d-i finish-install/reboot_in_progress note
"@
    Set-Content -Path $FilePath -Value $content -Encoding UTF8
}

# --- INITIALISATION DES CHEMINS ---

$VBoxManage = Get-VBoxManagePath
if (-not $VBoxManage) { Write-Error "VirtualBox non trouvé."; exit 1 }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$guestScriptsPath = Join-Path $projectRoot "guest"
$defaultIso = Join-Path $projectRoot "iso\debian-13.iso"
$preseedPath = Join-Path $projectRoot "cloud-init\preseed\preseed.cfg"
$diskRoot = Join-Path $projectRoot "vdi"
if (-not (Test-Path $diskRoot)) { New-Item $diskRoot -ItemType Directory | Out-Null }

# --- SÉLECTION DU TYPE ET RÔLE ---

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

# --- CONFIGURATION RÉSEAU ET RESSOURCES ---

if ($vmTypeChoice -eq "3") {
    $intNetName = "DMZ"
    $OvaPath = Join-Path $projectRoot "ova/firewall-$fwRole.ova"
} else {
    Write-Host "1) DMZ (192.168.10.0/24)`n2) LAN (192.168.20.0/24)"
    $netChoice = Read-Choice "Réseau de la VM" @("1", "2")
    $intNetName = if ($netChoice -eq "1") { "DMZ" } else { "LAN" }
}

$defaultName = switch ($vmTypeChoice) { "1" { "client" }; "2" { "srv-$serverRole" }; "3" { "firewall-$fwRole" } }
$name = Read-Host "Nom de la VM (Entrée = $defaultName)"
$name = if ($name) { $name } else { $defaultName }

# Ajustement ressources
$memory = if ($vmTypeChoice -eq "1") { 4096 } else { 1024 }
$diskSizeMb = if ($serverRole -eq "backup") { 51200 } else { 10240 } # 50Go pour Backup

# --- CRÉATION DE LA VM ---

if ($vmTypeChoice -eq "3") {
    & $VBoxManage import $OvaPath --vsys 0 --vmname $name
    if ($fwRole -eq "external") {
        & $VBoxManage modifyvm $name --nic1 nat --nic2 intnet --intnet2 DMZ
    } else {
        & $VBoxManage modifyvm $name --nic1 intnet --intnet1 LAN --nic2 intnet --intnet2 DMZ
    }
} else {
    $IsoPath = if ($IsoPath -and (Test-Path $IsoPath)) { $IsoPath } else { $defaultIso }
    & $VBoxManage createvm --name $name --ostype Debian_64 --register
    & $VBoxManage modifyvm $name --memory $memory --vram 128 --nic1 intnet --intnet1 $intNetName --nic2 nat

    # Stockage
    & $VBoxManage storagectl $name --name "SATA" --add sata
    $diskPath = Join-Path $diskRoot "$name.vdi"
    & $VBoxManage createhd --filename $diskPath --size $diskSizeMb
    & $VBoxManage storageattach $name --storagectl "SATA" --port 0 --type hdd --medium $diskPath
    & $VBoxManage storageattach $name --storagectl "SATA" --port 1 --type dvddrive --medium $IsoPath

    # Unattended
    $scriptFiles = @("common.sh")
    if ($serverRole) { $scriptFiles += "server-$serverRole.sh" }
    
    $scriptEntries = @()
    foreach ($sf in $scriptFiles) {
        $sp = Join-Path $guestScriptsPath $sf
        if (Test-Path $sp) {
            $content = (Get-Content $sp -Raw) -replace "`r`n", "`n"
            $scriptEntries += [pscustomobject]@{ Name = $sf; Content = $content }
        }
    }

    New-PreseedFile -FilePath $preseedPath -AdminUser $AdminUser -AdminPassword $AdminPassword -RootPassword $RootPassword -Hostname $name -ScriptFiles $scriptEntries -InstallGnome ($vmTypeChoice -eq "1")
    & $VBoxManage unattended install $name --iso $IsoPath --script-template $preseedPath --user $AdminUser --user-password $AdminPassword --admin-password $RootPassword --start-vm headless
}

Write-Host "VM '$name' prête. Réseau: NAT + intnet '$intNetName'."