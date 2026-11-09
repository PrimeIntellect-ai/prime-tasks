#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'SEQ' > /home/user/sequences.txt
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
ATGCGTACGTACCTACCTAGCTAGCTAGCAAGCTAGCTAGCTAGCTAGCAAGCTAGCAAGCTAGCTACCTAGCTAGCTAGCTAGCTAGCTAGCTAG
SEQ

    chmod -R 777 /home/user
