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

function Get-VBoxManagePath {
    $defaultPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $defaultPath) {
        return $defaultPath
    }

    $fromEnv = $env:VBOX_MSI_INSTALL_PATH
    if ($fromEnv) {
        $candidate = Join-Path $fromEnv "VBoxManage.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$ValidValues
    )

    while ($true) {
        $value = Read-Host $Prompt
        if ($ValidValues -contains $value) {
            return $value
        }
        Write-Host "Choix invalide. Valeurs autorisées: $($ValidValues -join ', ')"
    }
}

function Get-PlainTextPassword {
    param([securestring]$SecurePassword)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function New-IsoFromFolder {
    param(
        [string]$SourcePath,
        [string]$IsoPath,
        [string]$VolumeName = "SCRIPTS"
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Dossier source introuvable: $SourcePath"
    }

    $isoDir = Split-Path -Parent $IsoPath
    if (-not (Test-Path $isoDir)) {
        New-Item -Path $isoDir -ItemType Directory | Out-Null
    }

    try {
        $fs = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fs.FileSystemsToCreate = 3
        $fs.VolumeName = $VolumeName
        $fs.Root.AddTree($SourcePath, $false)
        $result = $fs.CreateResultImage()
        $imageStream = $result.ImageStream

        $unk = [System.Runtime.InteropServices.Marshal]::GetIUnknownForObject($imageStream)
        try {
            $comStream = [System.Runtime.InteropServices.Marshal]::GetTypedObjectForIUnknown(
                $unk,
                [System.Runtime.InteropServices.ComTypes.IStream]
            )
        } finally {
            [System.Runtime.InteropServices.Marshal]::Release($unk) | Out-Null
        }
        $stat = New-Object System.Runtime.InteropServices.ComTypes.STATSTG
        $comStream.Stat([ref]$stat, 0)
        $remaining = [int64]$stat.cbSize

        $bufferSize = 1024 * 1024
        $buffer = New-Object byte[] $bufferSize
        $bytesReadPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)

        $output = New-Object -ComObject ADODB.Stream
        $output.Type = 1
        $output.Open()

        try {
            while ($remaining -gt 0) {
                $toRead = [Math]::Min($bufferSize, $remaining)
                $comStream.Read($buffer, $toRead, $bytesReadPtr)
                $bytesRead = [System.Runtime.InteropServices.Marshal]::ReadInt32($bytesReadPtr)
                if ($bytesRead -le 0) {
                    break
                }
                $output.Write($buffer[0..($bytesRead - 1)])
                $remaining -= $bytesRead
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($bytesReadPtr)
        }

        $output.SaveToFile($IsoPath, 2)
        $output.Close()
    } catch {
        throw "Création ISO échouée (IMAPI2). $_"
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
        $content = $script.Content
        $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

        $scriptCommands += ('in-target /bin/sh -c "printf %s {0} | base64 -d > /home/{1}/{2}; chmod +x /home/{1}/{2}"' -f $base64, $AdminUser, $fileName)
        $scriptCommands += ('in-target /bin/sh -c "printf %s {0} | base64 -d > /opt/projet-reseaux/guest/{1}; chmod +x /opt/projet-reseaux/guest/{1}"' -f $base64, $fileName)
    }

    $scriptCommands += ('in-target /bin/sh -c "chown -R {0}:{0} /home/{0}"' -f $AdminUser)
    $lateCommand = ($scriptCommands -join "; ")

    $taskselLines = if ($InstallGnome) {
        @"
tasksel tasksel/first multiselect standard, gnome-desktop
d-i pkgsel/run_tasksel boolean true
"@
    } else {
        @"
d-i pkgsel/run_tasksel boolean false
"@
    }

    $content = @"
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
d-i netcfg/get_hostname string $Hostname
d-i netcfg/get_domain string $Domain

d-i passwd/root-login boolean true
d-i passwd/root-password password $RootPassword
d-i passwd/root-password-again password $RootPassword
d-i passwd/make-user boolean true
d-i passwd/user-fullname string $AdminUser
d-i passwd/username string $AdminUser
d-i passwd/user-password password $AdminPassword
d-i passwd/user-password-again password $AdminPassword

d-i clock-setup/utc boolean true
d-i time/zone string Europe/Paris

d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

$taskselLines
d-i pkgsel/include string
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string default

d-i preseed/late_command string \
in-target /bin/sh -c "echo $Hostname > /etc/hostname"; \
in-target /bin/sh -c "sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT=\"fr\"/' /etc/default/keyboard"; \
in-target /bin/sh -c "sed -i 's/^XKBVARIANT=.*/XKBVARIANT=\"oss\"/' /etc/default/keyboard"; \
$lateCommand

d-i finish-install/reboot_in_progress note
"@

    $dir = Split-Path -Parent $FilePath
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory | Out-Null
    }

    Set-Content -Path $FilePath -Value $content -Encoding UTF8
}

$VBoxManage = Get-VBoxManagePath
if (-not $VBoxManage) {
    Write-Error "VirtualBox non trouvé. Installez VirtualBox ou définissez VBOX_MSI_INSTALL_PATH."
    exit 1
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$guestScriptsPath = Join-Path $projectRoot "guest"
$defaultIso = Join-Path $projectRoot "iso\debian-13.iso"
$defaultOva = Join-Path $projectRoot "ova\firewall.ova"
$preseedDir = Join-Path $projectRoot "cloud-init\preseed"
$preseedPath = Join-Path $preseedDir "preseed.cfg"
$diskRoot = Join-Path $projectRoot "vdi"
if (-not (Test-Path $diskRoot)) {
    New-Item -Path $diskRoot -ItemType Directory | Out-Null
}

function Get-ExistingVmNames {
    param([string]$VBoxManagePath)

    $names = @()
    try {
        $lines = & $VBoxManagePath list vms 2>$null
        foreach ($line in $lines) {
            if ($line -match '"(.+?)"') {
                $names += $matches[1]
            }
        }
    } catch {
        return @()
    }
    return $names
}

function Get-UniqueVmName {
    param(
        [string]$DesiredName,
        [string[]]$ExistingNames
    )

    if (-not ($ExistingNames -contains $DesiredName)) {
        return $DesiredName
    }

    $i = 1
    while ($true) {
        $candidate = "$DesiredName-$i"
        if (-not ($ExistingNames -contains $candidate)) {
            return $candidate
        }
        $i++
    }
}

Write-Host "1) Client"
Write-Host "2) Serveur"
Write-Host "3) Pare-feu (OVA)"
$vmTypeChoice = Read-Choice "Choix" @("1", "2", "3")

$serverRole = $null
if ($vmTypeChoice -eq "2") {
    Write-Host "1) WEB"
    Write-Host "2) DNS"
    Write-Host "3) DHCP"
    Write-Host "4) MAIL"
    Write-Host "5) VPN"
    Write-Host "6) BDD"
    $roleChoice = Read-Choice "Type de serveur" @("1", "2", "3", "4", "5", "6")
    $serverRole = switch ($roleChoice) {
        "1" { "web" }
        "2" { "dns" }
        "3" { "dhcp" }
        "4" { "mail" }
        "5" { "vpn" }
        "6" { "db" }
    }
}

$fwRole = $null
if ($vmTypeChoice -eq "3") {
    Write-Host "1) Pare-feu Externe"
    Write-Host "2) Pare-feu Interne"
    $fwChoice = Read-Choice "Type de pare-feu" @("1", "2")
    $fwRole = switch ($fwChoice) {
        "1" { "external" }
        "2" { "internal" }
    }
}


# Gestion automatique du réseau pour les firewalls
if ($vmTypeChoice -eq "3") {
    if ($fwRole -eq "external") {
        $intNetName = "DMZ"
        $ovaFile = Join-Path $projectRoot "ova/firewall-externe.ova"
    } elseif ($fwRole -eq "internal") {
        $intNetName = "DMZ"
        $ovaFile = Join-Path $projectRoot "ova/firewall-interne.ova"
    }
} else {
    Write-Host "1) DMZ (192.168.10.0/24)"
    Write-Host "2) LAN (192.168.20.0/24)"
    $netChoice = Read-Choice "Réseau de la VM" @("1", "2")
    $intNetName = if ($netChoice -eq "1") { "DMZ" } else { "LAN" }
}


$defaultName = switch ($vmTypeChoice) {
    "1" { "client" }
    "2" { "srv-$serverRole" }
    "3" { "firewall-$fwRole" }
}

$name = Read-Host "Nom de la VM (Entrée = $defaultName)"
if (-not $name) {
    $name = $defaultName
}

$existingNames = Get-ExistingVmNames -VBoxManagePath $VBoxManage
$uniqueName = Get-UniqueVmName -DesiredName $name -ExistingNames $existingNames
if ($uniqueName -ne $name) {
    Write-Host "Nom déjà utilisé. Nouveau nom: $uniqueName"
    $name = $uniqueName
}

$memory = switch ($vmTypeChoice) {
    "1" { 4096 }
    "2" { 1024 }
    "3" { 1024 }
}

$vram = switch ($vmTypeChoice) {
    "1" { 256 }
    "2" { 128 }
    "3" { 128 }
}

$graphicsController = "VMSVGA"
$accel3d = if ($vmTypeChoice -eq "1") { "on" } else { "off" }

$cpus = 1
$diskSizeMb = switch ($vmTypeChoice) {
    "1" { 20480 }
    "2" { 10240 }
    "3" { 10240 }
}

$useUnattended = if ($vmTypeChoice -eq "3") { $false } else { $true }

if ($vmTypeChoice -eq "3") {
    # Sélection automatique du fichier OVA selon le type de pare-feu
    if ($fwRole -eq "external") {
        $OvaPath = $ovaFile
    } elseif ($fwRole -eq "internal") {
        $OvaPath = $ovaFile
    }
    if (-not (Test-Path $OvaPath)) {
        Write-Error "OVA introuvable: $OvaPath"
        exit 1
    }

    & $VBoxManage import $OvaPath --vsys 0 --vmname $name
    & $VBoxManage modifyvm $name --memory $memory --cpus $cpus --vram $vram --graphicscontroller $graphicsController --accelerate3d $accel3d --accelerate2dvideo off
    if ($fwRole -eq "external") {
        # Interface 1 : NAT, Interface 2 : DMZ
        & $VBoxManage modifyvm $name --nic1 nat --nictype1 82540EM --cableconnected1 on
        & $VBoxManage modifyvm $name --nic2 intnet --intnet2 DMZ --nictype2 82540EM --cableconnected2 on
    } elseif ($fwRole -eq "internal") {
        # Interface 1 : LAN, Interface 2 : DMZ
        & $VBoxManage modifyvm $name --nic1 intnet --intnet1 LAN --nictype1 82540EM --cableconnected1 on
        & $VBoxManage modifyvm $name --nic2 intnet --intnet2 DMZ --nictype2 82540EM --cableconnected2 on
    }
} else {
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

    & $VBoxManage createvm --name $name --ostype Debian_64 --register
    & $VBoxManage modifyvm $name --memory $memory --cpus $cpus --vram $vram --graphicscontroller $graphicsController --accelerate3d $accel3d --accelerate2dvideo off
    & $VBoxManage modifyvm $name --nic1 intnet --intnet1 $intNetName --nictype1 82540EM --cableconnected1 off
    & $VBoxManage modifyvm $name --nic2 nat --nictype2 82540EM --cableconnected2 on

    & $VBoxManage storagectl $name --name "SATA" --add sata --controller IntelAhci
    $diskPath = Join-Path $diskRoot "$name.vdi"
    & $VBoxManage createhd --filename $diskPath --size $diskSizeMb --variant Standard
    & $VBoxManage storageattach $name --storagectl "SATA" --port 0 --type hdd --medium $diskPath
    & $VBoxManage storageattach $name --storagectl "SATA" --port 1 --type dvddrive --medium $IsoPath


    if ($useUnattended) {
        try {
            $scriptFiles = @("common.sh")
            if ($vmTypeChoice -eq "2") {
                $scriptFiles += "server-$serverRole.sh"
            } else {
                $scriptFiles += "client.sh"
            }

            $scriptEntries = @()
            foreach ($scriptFile in $scriptFiles) {
                $scriptPath = Join-Path $guestScriptsPath $scriptFile
                if (Test-Path $scriptPath) {
                    # Conversion CRLF -> LF pour compatibilité Linux
                    $content = (Get-Content -Path $scriptPath -Raw) -replace "`r`n", "`n"
                    if ($null -eq $content) {
                        $content = ""
                    }
                    $scriptEntries += [pscustomobject]@{
                        Name    = $scriptFile
                        Content = $content
                    }
                }
            }

            $installGnome = ($vmTypeChoice -eq "1")
            New-PreseedFile -FilePath $preseedPath -AdminUser $AdminUser -AdminPassword $AdminPassword -RootPassword $RootPassword -Hostname $name -ScriptFiles $scriptEntries -InstallGnome $installGnome

            $unattendedOutput = & $VBoxManage unattended install $name --iso $IsoPath --script-template $preseedPath --user $AdminUser --user-password $AdminPassword --admin-password $RootPassword --full-user-name $AdminUser --hostname "$name.local" --locale "fr_FR" --time-zone "Europe/Paris" --country "FR" --language "fr" --package-selection-adjustment minimal --start-vm headless 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw ($unattendedOutput | Out-String)
            }
            try {
                & $VBoxManage controlvm $name setlinkstate1 on
            } catch {
                Write-Warning "Impossible d'activer la carte réseau 1 après installation."
            }
        } catch {
            Write-Error "Installation automatique échouée.`n$($_.Exception.Message)"
        }
    }
}

if (-not $useUnattended) {
    & $VBoxManage startvm $name --type headless
}

Write-Host "VM '$name' prête. Réseau: NAT + intnet '$intNetName'."
