#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/seqs.fasta
>seq1
AAACGTCGTCGTAGCTAGCT
>seq2
CGTACGTCGTCGTAGCTAGC
>seq3
TTTCGTCGTCGTAGCTAGCT
>seq4
GGGCGTCGTCGTAGCTAGCT
>seq5
ATACGTCGTCGTAGCTAGCT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
