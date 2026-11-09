#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/base_en.tsv
ID001	ui_button	Save
ID002	ui_button	Cancel
ID003	menu	File
ID004	menu	Edit
ID005	dialog	Are you sure?
ID006	dialog	Warning
EOF

    cat << 'EOF' > /home/user/trans_fr.tsv
ID001	 Sauvegarder 
ID002	Annuler
ID003	Fichier
ID004	Modifier 
ID005	 Êtes-vous sûr ?
ID006	 Avertissement
EOF

    chmod -R 777 /home/user
