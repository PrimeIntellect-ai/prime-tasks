#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/loc_data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/loc_data/en_master.csv
Key,English
APP_GREETING,Hello
APP_FAREWELL,Goodbye
APP_ERROR,Error occurred
APP_RETRY,Try again
APP_HELP,Help menu
EOF

    cat << 'EOF' > /tmp/fr_fr.utf8
[APP_GREETING] = "Bonjour"
[APP_ERROR] = "Erreur survenue"
[APP_HELP] = "Menu d'aide"
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/fr_fr.utf8 > /home/user/loc_data/fr_fr.txt

    cat << 'EOF' > /tmp/es_es.utf8
Key: APP_GREETING | Val: "Hola"
Key: APP_FAREWELL | Val: "Adiós"
Key: APP_RETRY | Val: "Reintentar"
EOF
    iconv -f UTF-8 -t UTF-16LE /tmp/es_es.utf8 > /home/user/loc_data/es_es.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
