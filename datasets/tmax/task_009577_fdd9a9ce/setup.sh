#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy biopython

    mkdir -p /home/user/data/
    cat << 'EOF' > /home/user/data/input.fasta
>seq1_match
ATGCGTACGTGGGGGGGGGGGGGGGGGGGGTACGCATGC
>seq2_no_match_start
TTGCGTACGTGGGGGGGGGGGGGGGGGGGGTACGCATGC
>seq3_match
ATGCGTACGTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAATACGCATGC
>seq4_no_match_end
ATGCGTACGTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAATACGCATGA
>seq5_match
ATGCGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGCATGC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
