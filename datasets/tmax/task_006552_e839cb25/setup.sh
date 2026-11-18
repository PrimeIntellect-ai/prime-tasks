#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_resources.txt
STR:4150505f4e414d45:4d79417070
BOOL:454e41424c455f4c4f4753:74727565
STR:4150495f454e44504f494e54:68747470733a2f2f6170692e6578616d706c652e636f6d
BOOL:555345525f4f4e424f415244494e47:66616c7365
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
