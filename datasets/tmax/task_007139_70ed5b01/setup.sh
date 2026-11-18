#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest jupyter nbconvert numpy scipy emcee

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/data/input.fasta
>Seq1
ACGTACGTACGTACGT
>Seq2
ATATATATATATATAT
>Seq3
GGCCGGCCGGCCGGCC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
