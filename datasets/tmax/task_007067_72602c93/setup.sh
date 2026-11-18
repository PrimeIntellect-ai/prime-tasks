#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming /home/user/outgoing /home/user/extracted
    mkdir -p /tmp/setup_configs/configs
    mkdir -p /tmp/setup_configs/malicious

    cat << 'EOF' > /tmp/setup_configs/configs/app1.conf
SERVER_PORT=8080
LOG_LEVEL=WARN
ENABLE_FEATURE_X=true
EOF

    cat << 'EOF' > /tmp/setup_configs/configs/app2.conf
SERVER_PORT=9090
LOG_LEVEL=DEBUG
ENABLE_FEATURE_X=false
EOF

    cat << 'EOF' > /tmp/setup_configs/malicious/escape.txt
YOU HAVE BEEN HACKED
EOF

    cat << 'EOF' > /tmp/setup_configs/malicious/absolute.txt
OVERWRITE SYSTEM
EOF

    cd /tmp/setup_configs
    tar -Pczf /tmp/update.tar.gz configs/app1.conf configs/app2.conf ../setup_configs/malicious/escape.txt /tmp/setup_configs/malicious/absolute.txt
    cd /tmp
    split -b 500 /tmp/update.tar.gz /home/user/incoming/update.tar.gz.part
    rm -rf /tmp/setup_configs /tmp/update.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
