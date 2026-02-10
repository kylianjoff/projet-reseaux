# Projet Réseau - Déploiement automatique de VM VirtualBox

## Objectif
Ce dépôt permet de **créer et installer automatiquement** des VM (clients, serveurs, pare‑feu) dans VirtualBox. Le script crée les VM, configure le réseau NAT + DMZ/LAN, lance l’installation Debian **sans interaction**, injecte les scripts Bash **pendant l’installation** et configure automatiquement le clavier en français.

---

## Prérequis
- Windows + PowerShell
- VirtualBox installé

---

## Script principal
Le script se trouve dans :

- [host/create-vm.ps1](host/create-vm.ps1)

Il **crée la VM**, **attache le disque**, **configure le réseau**, **démarre l’installation automatique** et **injecte les scripts**.

### Comptes créés automatiquement (par défaut)
- Utilisateur administrateur : `administrateur` / mot de passe `admin`
- Root : mot de passe `root`

Ces valeurs peuvent être modifiées via les paramètres du script.

---

## Réseaux
Chaque VM est configurée avec **2 cartes réseau** :

1. **NAT** (accès Internet pendant l’installation)
2. **Intnet** (réseau interne)
   - DMZ → 192.168.10.0/24
   - LAN → 192.168.20.0/24

**Important :** la carte interne (Intnet) est **désactivée pendant l’installation** afin d’éviter les erreurs de dépôt, puis **réactivée après le démarrage**.

---

## Injection des scripts pendant l’installation
Le script injecte directement les fichiers Bash depuis [guest](guest) via le preseed, sans dépendre d’un ISO ni d’un dossier partagé.

Selon le type de VM :
- **Serveur** : `common.sh` + `server-<role>.sh`
- **Client** : `common.sh` + `client.sh`

Emplacements créés :
- `/home/administrateur/` (scripts exécutables)
- `/opt/projet-reseaux/guest/` (copie complète)

---

## Procédure d’utilisation
1. Lancer PowerShell dans le dossier du projet
2. Exécuter le script

Le script pose quelques questions (type de VM, rôle, réseau, nom), puis l’installation se fait **sans interaction** dans l’installateur Debian.

---

## Paramètres utiles
Le script accepte des paramètres pour éviter de saisir des chemins :

- `-IsoPath` → chemin de l’ISO Debian
- `-OvaPath` → chemin de l’OVA pare‑feu
- `-AdminUser` → utilisateur admin (par défaut `administrateur`)
- `-AdminPassword` → mot de passe admin (par défaut `admin`)
- `-RootPassword` → mot de passe root (par défaut `root`)

---

## Résultat attendu
- VM créée et démarrée automatiquement
- Debian installée sans intervention
- Clavier en français (AZERTY)
- Scripts présents dans `/home/administrateur/` et `/opt/projet-reseaux/guest`
- Réseau configuré en NAT + DMZ/LAN
- **Clients** avec bureau GNOME

---

## Dépannage rapide
- Vérifier que VirtualBox est installé
- Vérifier le chemin de l’ISO/OVA
- S’assurer que l’ISO Debian est compatible avec l’installation automatique VirtualBox
- Si `apt update` échoue à cause du CD‑ROM, relancer l’installation (le preseed désactive les entrées CD‑ROM)

---

En cas de problème / bug dont la solution n'est pas présente dans cette documentation, vous pouvez me contacter.