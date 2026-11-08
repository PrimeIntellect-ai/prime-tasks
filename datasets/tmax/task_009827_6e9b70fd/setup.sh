#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/translation_logs.csv
timestamp,lang,chars_translated
1620001,es-ES,120
1620002,fr-FR,200
1620003,es-ES,300
1620004,es-ES,-50
1620005,es-ES,5500
1620006,es-ES,450
1620007,de-DE,100
1620008,es-ES,300
1620009,es-ES,0
1620010,es-ES,150
1620011,es-ES,600
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
