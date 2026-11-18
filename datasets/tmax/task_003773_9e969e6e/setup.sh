#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sequences.fasta
>seq_train
ATGCGTACTGATCGTACGATCGTACGATCGTACGATCGTACGATCGTACGATCGTACGAT
>seq_A
ATGCGTACGTTAGCTAGCCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCT
>seq_B
AAAAAAAAAACCCCCCCCCCGGGGGGGGGGTTTTTTTTTTAAAAAAAAAACCCCCCCCCC
>seq_C
ATGCGTACTGATCGTACGATCGTACGATCGTACGATCGTACGATCGTACGATCGTACGAT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
