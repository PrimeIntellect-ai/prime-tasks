#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/translation_logs.csv
timestamp,locale,words
2023-10-01T08:00:00Z,fr-FR,100
2023-10-01T12:00:00Z,fr-FR,200
2023-10-01T16:00:00Z,es-ES,500
2023-10-02T09:00:00Z,fr-FR,150
2023-10-03T10:00:00Z,fr-FR,300
2023-10-04T10:00:00Z,fr-FR,50
2023-10-05T11:00:00Z,fr-FR,100
2023-10-06T10:00:00Z,es-ES,200
2023-10-07T08:00:00Z,fr-FR,400
2023-10-08T09:00:00Z,fr-FR,350
EOF

    chmod -R 777 /home/user
