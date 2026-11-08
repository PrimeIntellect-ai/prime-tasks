#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/loc_telemetry.csv
timestamp,locale,key,render_time_ms
2023-10-15T10:00:15Z,es-ES,btn_ok,40
1697364020,fr-FR,btn_ok,60
2023-10-15T10:00:55Z,es-ES,btn_cancel,50
1697364130,de-DE,hdr_title,100
2023-10-15T10:04:05Z,fr-FR,msg_error,80
EOF

    chmod -R 777 /home/user
