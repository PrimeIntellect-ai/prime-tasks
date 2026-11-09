#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.fasta
>seqA1
ATGCATGCATGC
>seqB2
ATGC
>seqC3
ATGCATGCATGCATGCATGCATGC
>seqD4
A
EOF

    chmod -R 777 /home/user
