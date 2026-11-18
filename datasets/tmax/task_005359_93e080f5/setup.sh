#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/loc_data/
    cat << 'EOF' > /home/user/loc_data/raw_logs.txt
[2023-10-01T10:05:00Z] LANG:fr-FR | SRC:Cat | TR:Chat
[2023-10-01T10:00:00Z] LANG:es-ES | SRC:Hello | TR:Hola
[2023-10-01T10:02:00Z] LANG:es-ES | SRC:Yes | TR:Si
[2023-10-01T10:04:00Z] LANG:es-ES | SRC:Good morning | TR:Buenos dias
[MALFORMED] No lang here
[2023-10-01T10:06:00Z] LANG:es-ES | SRC:Thanks | TR:Gracias
[2023-10-01T10:07:00Z] LANG:fr-FR | SRC:Dog | TR:Chien
[2023-10-01T10:08:00Z] LANG:fr-FR | SRC:Bird | TR:Oiseau
[2023-10-01T10:09:00Z] LANG:fr-FR | SRC:Apple | TR:Pomme
[2023-10-01T10:09:30Z] LANG:es-ES | SRC: | TR:Nada
[2023-10-01T10:10:00Z] LANG:es-ES | SRC:Bye | TR:
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
