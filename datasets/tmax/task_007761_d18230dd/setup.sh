#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sequences.fasta
>seq1
ACGTACGTACGT
>seq2
CCCCGGGGTTTT
>seq3_duplicate_of_1
ACGTACGTACGT
>seq4
ATATATATATAT
>seq5_duplicate_of_2
CCCCGGGGTTTT
>seq6
TTTTTTTTTTTT
>seq7_duplicate_of_4
ATATATATATAT
EOF

    chmod -R 777 /home/user
