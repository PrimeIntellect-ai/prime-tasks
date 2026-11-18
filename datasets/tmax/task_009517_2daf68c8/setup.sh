#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/base_strings.csv
ERR_01,File not found
BTN_OK,OK
MSG_GREET,Welcome back to the system
MSG_BYE,Goodbye
EOF

    cat << 'EOF' > /home/user/translations_raw.csv
ERR_01,fr,Fichier introuvable,1620000000
ERR_01,fr,Fichier non trouvé,1620000050
BTN_OK,fr,D'accord,1620000000
MSG_GREET,es,Bienvenido al sistema,1620000100
MSG_GREET,es,Bienvenido,1620000010
MSG_BYE,it,Addio,1620000000
MSG_BYE,it,Arrivederci,1620000200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
