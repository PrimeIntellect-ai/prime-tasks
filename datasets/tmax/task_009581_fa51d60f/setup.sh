#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGTACGTTAG
>seq2
CCGGAATTGC
>seq3
TTTAAACCCGGG
>seq4
GATCGATCGATC
>seq5
AAAAACCCCCGGGGGTTTTT
EOF

    chmod -R 777 /home/user
