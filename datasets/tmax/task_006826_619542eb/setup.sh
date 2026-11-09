#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/translations_raw.csv
key,lang,text,timestamp
BTN_OK,en,OK,1600000000
BTN_OK,en,Okay,1600000005
BTN_OK,fr,D'accord,1600000000
BTN_OK,es,Aceptar,1600000000
BTN_CANCEL,en,Cancel,1600000000
BTN_CANCEL,fr,Annuler,1600000000
BTN_CANCEL,fr,Annuler!,1600000002
ERR_404,en,Not Found,1600000000
ERR_404,es,No Encontrado,1600000000
TITLE_MAIN,en,Main Menu,1600000000
TITLE_MAIN,fr,Menu Principal,1600000000
TITLE_MAIN,es,Menu Principal,1600000000
EOF

    chmod -R 777 /home/user
