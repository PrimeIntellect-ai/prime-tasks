#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/primers.fa
>Primer_A
ATGCGTACGTTAGCGTAC
>Primer_B
GCTAGCGCATAGCCGATA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
