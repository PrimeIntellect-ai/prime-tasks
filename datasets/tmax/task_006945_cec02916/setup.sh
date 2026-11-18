#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sequence.fasta
>seq1 synthetic DNA with period 3 property
ATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAG
ATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAG
ATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAGATGCGCTAG
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
