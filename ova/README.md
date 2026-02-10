## Dossier `ova/`

Ce dossier contient les fichiers OVA nécessaires à la création de certaines machines virtuelles du projet, notamment le pare-feu.

### Fichier OVA accepté
- **Seul le fichier OVA du pare-feu** est utilisé par le script d'automatisation (`host/create-vm.ps1`).
- Le fichier doit être nommé **`firewall.ova`** et placé dans ce dossier.

### Utilisation
Lors de l'exécution du script `create-vm.ps1`, ce fichier OVA sera utilisé pour importer et configurer automatiquement la machine virtuelle pare-feu. Si le fichier n'est pas présent ou mal nommé, le script demandera son emplacement ou échouera.

### Exemple de procédure
1. Exporter ou récupérer le fichier OVA du pare-feu (par exemple depuis VirtualBox ou une source fournie).
2. Renommer le fichier en `firewall.ova` si nécessaire.
3. Placer ce fichier dans ce dossier `ova/`.

**Aucun autre fichier OVA n'est accepté par le script d'installation automatique.**
