#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/primer.fasta
>primer_1
ATGCGTACGTTAGCTAGCTAGCTGATC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
