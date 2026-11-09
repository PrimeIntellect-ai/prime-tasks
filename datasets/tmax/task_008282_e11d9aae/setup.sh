#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy h5py

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sequences.fasta
>seq1
ATGCGTACGTAGCTAG
>seq2
GGGCCCCAAATTT
>seq3
ANNACT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
