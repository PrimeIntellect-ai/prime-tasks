#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sequences.fasta
>seq1
AACTGCTAGCTAGCTAGCTA
>seq2
GGGCCCTTTTAAAA
>seq3
ACGTACGTACGT
EOF

    chmod -R 777 /home/user
