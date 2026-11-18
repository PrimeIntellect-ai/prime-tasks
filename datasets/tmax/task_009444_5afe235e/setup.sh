#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/primers.txt
ATGCGTACGTAGCTAG
GCGCGCGCGCGC
ATATATATATAT
ATGC
GGGGATATCCCC
CGCGATATCGCG
AATT
GCTAGCTAGCTA
EOF

    chmod -R 777 /home/user
