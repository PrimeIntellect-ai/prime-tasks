#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.fasta
>Seq1
ATCGATCGATCGA
>Seq2
ATCGATTTTTTTT
>Seq3
TTTTTGGGGGCCC
>Seq4
GGCCCAAAAAAAA
>Seq5
AAAAATCGATCGA
EOF

    chmod -R 777 /home/user
