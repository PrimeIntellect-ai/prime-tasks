#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGC
>seq2
ATATAT
>seq3
GGCGCG
>seq4
ATGC
>seq5
CCGGAT
EOF

    chmod -R 777 /home/user
