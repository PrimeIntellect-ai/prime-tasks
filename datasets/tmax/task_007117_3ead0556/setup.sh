#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy biopython

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
>target_gene
GGCCATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCGGCC
>seq3
ATATATATATATATATATATATATATATATATAT
EOF

    chmod -R 777 /home/user
