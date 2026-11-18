#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reads.fasta
>Read_001
ATCGGACCTACAGGGCCCAAATGTTGCAGATCG
>Read_002
GACCTACATTTTAAAATGTTGCAG
>Read_003
AGTCGACCTACAGCGGGCGTGTTGCAGCTTA
>Read_004
ATCGATCGATCG
>Read_005
TGTTGCAGATCGGACCTACA
EOF

    chmod -R 777 /home/user
