#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.txt
AAAAAC
ACACAC
ACACAA
GGGGGG
EOF

    chmod -R 777 /home/user
