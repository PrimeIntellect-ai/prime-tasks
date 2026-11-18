#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.csv
KEY,LANG,TEXT
BTN_OK,en,  OK  
BTN_OK,es,Aceptar
BTN_CANCEL,en,Cancel
BTN_CANCEL,es,  Cancelar  
GREETING,ja, こんにちは   世界 
GREETING,ja,こんにちは 世界 (override)
ERR_01,ar,خطأ
BTN_OK,es,  Aceptar  Definitivo 
MENU_FILE,en, File   Menu 
MENU_FILE,en,File Menu
EOF

    chmod -R 777 /home/user
