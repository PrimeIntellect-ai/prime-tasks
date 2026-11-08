#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/reads.txt
AAAAAAAAAAAAAAAAAAAAAAAGATTACA
GATTACACCCCCCCCCCCCCCCCCCCCCCC
GATTACAGGGGGGGGGGGGGGGGGGGGGGG
GATTACATTTTTTTTTTTTTTTTTTTTTTT
NNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
