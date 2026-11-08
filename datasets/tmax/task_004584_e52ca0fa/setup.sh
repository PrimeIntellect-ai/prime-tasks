#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mesh.dsl
Payment -> Auth
Payment -> Ledger
Auth -> DB
Ledger -> DB
DB -> NONE
Analytics -> DB
Notification -> Auth
Notification -> Analytics
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
