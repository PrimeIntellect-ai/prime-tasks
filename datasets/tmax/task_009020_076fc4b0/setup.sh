#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.fasta
>seq_01_synthetic
ATATATATATATATATATATATATATATAT
ATATATATATCGTCGTCGTCGTCGTCGTCG
ATATATATATATATATATATATATATATAT
ATATATATAT
EOF

    chmod -R 777 /home/user
