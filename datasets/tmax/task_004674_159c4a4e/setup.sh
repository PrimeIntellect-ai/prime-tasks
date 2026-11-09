#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCATGC
>seq2
ATGC
>seq3
GGGCCC
>seq4
AATT
>seq5
GCTAGCTA
GCTA
>seq6
ATATATAT
>seq7
GCGCGC
GCGC
EOF

    chmod -R 777 /home/user
