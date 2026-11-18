#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGTA
>seq2
GCGCGCGCGC
>seq3
ATATATATATATAT
>seq4
GGGCCC
>seq5
ATGCATGCATGCATGC
EOF

    chmod -R 777 /home/user
