#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/master_en_es.csv
string_id,en_text,es_text,status
STR_001,Hello world,Hola mundo,approved
STR_002,Save,Guardar,approved
STR_003,Cancel,,pending
STR_004,Delete,,pending
STR_006,Settings,Ajustes,approved
EOF

    cat << 'EOF' > /home/user/translator_deliveries.txt
Starting export job at 2023-10-01 10:00...
Processing batch 1...
[2023-10-01 10:00:05] UPDATE id="STR_003" translation="Cancelar"
[2023-10-01 10:00:10] UPDATE id="STR_004" translation="Borrar"
[2023-10-01 10:00:12] UPDATE id="STR_999" translation="Falso"
Network error detected. Connection reset by peer.
Retrying batch 1 and continuing...
Processing batch 1...
[2023-10-01 10:05:05] UPDATE id="STR_003" translation="Cancelar"
[2023-10-01 10:05:10] UPDATE id="STR_004" translation="Eliminar"
[2023-10-01 10:05:15] UPDATE id="STR_006" translation="Configuracion"
Export complete.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
