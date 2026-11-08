#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/input.fasta
>seq1
ATGCATGC
>seq2
GCGCGCGC
>seq3
ATATATAT
>seq4
ATGCGCAT
>seq5
GGGCCCCC
EOF

    chmod -R 777 /home/user
