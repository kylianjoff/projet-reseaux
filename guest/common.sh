if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	echo "Ce serveur a ete initialise automatiquement par le script de creation de VM. Il est possible que certaines configurations soient a revoir (ex: interface reseau, plage DHCP, etc.)." >&2
	echo ""
	echo "Jusqu'ici vous avez juste installe une VM, mais il reste a configurer le serveur/client/firewall pour que tout fonctionne."
	echo "Le script d'installation se trouve dans le dossier home de l'utilisateur administrateur (ex: /home/administrateur/server-dhcp.sh)."
	echo "Si ce fichier est manquant, vous pouvez toujours cloner le depot GitHub du projet et recuperer le script dans le dossier guest."
	echo "N'oubliez pas de rendre le script executable (chmod +x /home/administrateur/server-dhcp.sh) et de l'executer en root (sudo /home/administrateur/server-dhcp.sh) pour installer et configurer le serveur DHCP."
	echo ""
	echo "Depot GitHub : https://github.com/kylianjoff/projet-reseaux"
	echo "Documentation : https://kylianjoff.github.io/projet-reseaux/"
	echo ""
	echo "Si vous constatez des problemes, veuillez dans un premier temps lire la documentation. Sinon contactez moi."
	echo ""
	echo "Developpe par Kylian JULIA"
	echo ""
fi

require_root() {
	if [ "${EUID}" -ne 0 ]; then
		echo "Ce script doit etre execute en root. (su - puis mot de passe root)" >&2
		exit 1
	fi
}

ensure_whiptail() {
	if ! command -v whiptail >/dev/null 2>&1; then
		echo "whiptail introuvable. Installez le paquet whiptail." >&2
		exit 1
	fi
}

ui_input() {
	local title="$1" prompt="$2" default_value="$3"
	local value
	value=$(whiptail --title "$title" --inputbox "$prompt" 10 70 "$default_value" 3>&1 1>&2 2>&3) || return 1
	echo "$value"
}

ui_menu() {
	local title="$1" prompt="$2" default_index="$3"
	shift 3
	local options=("$@")
	local menu_items=()
	local i=1
	for opt in "${options[@]}"; do
		menu_items+=("$i" "$opt")
		i=$((i + 1))
	done
	whiptail --title "$title" --menu "$prompt" 14 70 6 \
		"${menu_items[@]}" \
		--default-item "$default_index" \
		3>&1 1>&2 2>&3
}

ui_msg() {
	local title="${1:-Message}" message="${2:-}"
	whiptail --title "$title" --msgbox "$message" 10 70
}

ui_info() {
	local title="${1:-Info}" message="${2:-}"
	whiptail --title "$title" --infobox "$message" 10 70
}