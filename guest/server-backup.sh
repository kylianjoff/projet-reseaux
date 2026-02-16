#!/bin/bash
set -euo pipefail

echo "== Configuration du Serveur de Backup =="
apt-get update && apt-get install -y rsync openssh-server

# Création d'un répertoire dédié aux sauvegardes
mkdir -p /storage/backups
chown -R ${ADMIN_USER}:${ADMIN_USER} /storage/backups

echo "== Serveur de Backup prêt (Destination: /storage/backups) =="