#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/loc_data

    cat << 'EOF' > /home/user/loc_data/raw_translations.txt
BTN_OK|1672531200|50.0|en-US
BTN_OK|2023-01-01T01:00:00Z|60.0|en-US
BTN_CANCEL|1672531200|40.0|fr-FR
ERR_404|2023-01-02T00:00:00Z|80.0|es-ES
ERR_404|1672617600|75.0|es-ES
MENU_FILE|1672621200|55.0|de-DE
MENU_FILE|2023-01-02T02:00:00Z|55.0|de-DE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
