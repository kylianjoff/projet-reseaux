## Dossier `iso/`

Ce dossier contient les images ISO nécessaires à la création des machines virtuelles du projet.

### ISO accepté
- **Seule l'image ISO de Debian 13** est supportée par le script d'automatisation (`host/create-vm.ps1`).
- Le fichier doit être téléchargé depuis le site officiel de Debian, renommé en **`debian-13.iso`** puis placé dans ce dossier.

### Utilisation
Lors de l'exécution du script `create-vm.ps1`, ce fichier ISO sera utilisé pour installer automatiquement les machines virtuelles (client ou serveur). Si le fichier n'est pas présent ou mal nommé, le script demandera son emplacement ou échouera.

### Exemple de procédure
1. Télécharger l'image ISO de Debian 13 (netinst ou DVD) depuis [debian.org](https://www.debian.org/download).
2. Renommer le fichier téléchargé en `debian-13.iso`.
3. Placer ce fichier dans ce dossier `iso/`.

**Aucune autre image ISO n'est acceptée par le script d'installation automatique.**