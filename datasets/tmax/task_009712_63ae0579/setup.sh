#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.fasta
>seq_001
CCGCGCGGCGCGCCATATATATATATATATCGCGCGCGCGATATATATATATCGCGCGCGCGCGCGATATATATATATCG
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
