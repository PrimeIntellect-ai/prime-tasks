#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libomp-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dna.fasta
>sequence_1
ATGCGTA
CGTAGCT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
