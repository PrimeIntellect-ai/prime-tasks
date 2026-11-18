#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest jupyter pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.fasta
>seq1
ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGAT
>seq2
AAAAATTTTTCCCCCGGGGGAAAAATTTTTCCCCCGGGGGAAAAATTTTT
>seq3
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG
>seq4
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC
>seq5
TCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTC
EOF

    chmod -R 777 /home/user
