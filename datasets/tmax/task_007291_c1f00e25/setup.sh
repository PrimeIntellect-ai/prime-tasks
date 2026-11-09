#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/reads.csv
id,sequence
seq1,ATGCGTA
seq2,GCGCGC
seq3,ATATAT
seq4,INVALID123
seq5,GATTACA
seq6,ATGCXGTA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
