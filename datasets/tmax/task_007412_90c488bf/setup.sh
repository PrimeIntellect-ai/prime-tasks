#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/genes.fasta
>seq1
ATGCGTAACGTACGTAGCTAGCTAGCATCGATCGATCGATCGA
>seq2
GGGGCCCCGGGGCCCCGGGGCCCC
>seq3
ATATATATATATATATATATATATATATATAT
EOF

    chmod -R 777 /home/user
