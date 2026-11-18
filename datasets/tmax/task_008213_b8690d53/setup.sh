#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/loc_metrics.csv
timestamp,locale,strings_translated,errors_reported
1700000000,fr-FR,1000,50
1700086400,de-DE,500,150
1700086400,de-DE,600,10
1700086400,de-DE,500,150
1700172800,ja-JP,50,20
1700259200,es-ES,200,42
1700259200,es-ES,200,42
1700345600,ko-KR,150,30
1700432000,it-IT,800,168
1700518400,pt-BR,105,22
EOF

    chmod -R 777 /home/user
