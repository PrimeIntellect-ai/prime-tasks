#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget jq rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_data
    cd /home/user/server_data

    cat << 'EOF' > data1.csv
timestamp,locale,msg_id,translation
1670000005,es_ES,welcome,"Hola
Mundo"
1670000001,fr_FR,bye,"Au revoir"
EOF

    cat << 'EOF' > data2.csv
timestamp,locale,msg_id,translation
1670000002,de_DE,error,"Fehler
aufgetreten
bitte warten"
1670000010,en_US,info,"  Update successful  "
EOF

    # To ensure the server starts in environments that might just source bashrc
    echo 'if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then (cd /home/user/server_data && python3 -m http.server 8080 > /dev/null 2>&1 &); fi' >> /etc/bash.bashrc

    chmod -R 777 /home/user
