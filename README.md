# Projet Réseau - Déploiement automatique de VM VirtualBox

## Objectif
Ce dépôt permet de **créer et installer automatiquement** des VM (clients, serveurs, pare‑feu) dans VirtualBox. Le script crée les VM, configure le réseau NAT + DMZ/LAN, lance l’installation Debian **sans interaction**, injecte les scripts Bash **pendant l’installation** et configure automatiquement le clavier en français.

---


## Prérequis
- Windows + PowerShell
- VirtualBox installé
- Télécharger le dossier ZIP contenant les fichiers `.iso` et `.ova` depuis le cloud [Lien vers les ressources](https://1drv.ms/u/c/71c7ddacee86e000/IQARzNaDJXJpTrXFSLH68Q5FAU2gsKkdJphCyzl9-6SwLwY?e=5SCjUi)
   - Décompresser le contenu dans le dossier du projet (les fichiers doivent se retrouver dans `iso/` et `ova/`)

---


## Script principal
Le script principal est :

- [host/create-vm.ps1](host/create-vm.ps1)

Il **crée la VM**, **attache le disque**, **configure le réseau**, **démarre l’installation automatique** et **injecte les scripts**.

### Comptes créés automatiquement (par défaut)
- Utilisateur administrateur : `administrateur` / mot de passe `admin`
- Root : mot de passe `root`

Ces valeurs peuvent être modifiées via les paramètres du script.

---


## Réseaux
Chaque VM est configurée avec **2 cartes réseau** :

- **Client/Serveur** :
   1. **NAT** (accès Internet pendant l’installation)
   2. **Intnet** (DMZ ou LAN, au choix)
- **Pare-feu externe** :
   1. **NAT**
   2. **DMZ**
- **Pare-feu interne** :
   1. **LAN**
   2. **DMZ**

**Important :** la carte interne (Intnet) est **désactivée pendant l’installation** pour les clients/serveurs afin d’éviter les erreurs de dépôt, puis **réactivée après le démarrage**.

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
1. Télécharger et décompresser le dossier ZIP contenant les fichiers `.iso` et `.ova` [Lien vers les ressources](https://1drv.ms/u/c/71c7ddacee86e000/IQARzNaDJXJpTrXFSLH68Q5FAU2gsKkdJphCyzl9-6SwLwY?e=5SCjUi)
2. Lancer PowerShell dans le dossier du projet
3. Exécuter le script :
   - `./host/create-vm.ps1`

Le script pose quelques questions (type de VM, rôle, réseau, nom). Pour les pare-feu, le choix du réseau est automatique :
   - **Pare-feu externe** : interface 1 = NAT, interface 2 = DMZ (utilise `ova/firewall-externe.ova`)
   - **Pare-feu interne** : interface 1 = LAN, interface 2 = DMZ (utilise `ova/firewall-interne.ova`)

L’installation se fait **sans interaction** dans l’installateur Debian pour les clients et serveurs.

---


## Paramètres utiles
Le script accepte des paramètres pour éviter de saisir des chemins :

- `-IsoPath` → chemin de l’ISO Debian (par défaut `iso/debian-13.iso`)
- `-OvaPath` → chemin de l’OVA pare‑feu (pour usage avancé, sinon automatique)
- `-AdminUser` → utilisateur admin (par défaut `administrateur`)
- `-AdminPassword` → mot de passe admin (par défaut `admin`)
- `-RootPassword` → mot de passe root (par défaut `root`)

---


## Résultat attendu
- VM créée et démarrée automatiquement
- Debian installée sans intervention
- Clavier en français (AZERTY)
- Scripts présents dans `/home/administrateur/` et `/opt/projet-reseaux/guest`
- Réseau configuré selon le type de VM (voir plus haut)
- **Clients** avec bureau GNOME

---

## Dépannage rapide
- Vérifier que VirtualBox est installé
- Vérifier le chemin de l’ISO/OVA
- S’assurer que l’ISO Debian est compatible avec l’installation automatique VirtualBox
- Si `apt update` échoue à cause du CD‑ROM, relancer l’installation (le preseed désactive les entrées CD‑ROM)

---

En cas de problème / bug dont la solution n'est pas présente dans cette documentation, vous pouvez me contacter.