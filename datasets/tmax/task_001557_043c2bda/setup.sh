#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/proteins.fasta
>Seq0
MKVLLAY
>Seq1
MKVAXYZ
>Seq2
MKAALPQ
>Seq3
MKVXYZZ
>Seq4
MKAXYAA
>Seq5
MLKVYYY
>Seq6
MLKZZZZ
>Seq7
MKVPPPO
>Seq8
MKAQQQQ
>Seq9
MLKAAAA
EOF

    chmod -R 777 /home/user
