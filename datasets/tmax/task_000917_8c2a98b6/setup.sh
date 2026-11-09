#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_translations.csv
HOME_BTN,en-US,Home,1600000000,APPROVED
HOME_BTN,en-US,Home (Old),1500000000,APPROVED
SUBMIT_BTN,fr-FR,Soumettre,1600000010,APPROVED
CANCEL_BTN,de-DE,,1600000020,DRAFT
ABOUT_US,en,About,1600000030,APPROVED
PROFILE,en-US,Profile,1600000040,REVIEW
SETTINGS,en-US,Settings,1600000050,APPROVED
HELP_BTN,en-US,Help,1600000060,APPROVED
HELP_BTN,en-US,Help me,1600000065,APPROVED
DASHBOARD,es-ES,Tablero,1600000070,DRAFT
DASHBOARD,es-ES,Tablero de mandos,1600000080,DRAFT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
