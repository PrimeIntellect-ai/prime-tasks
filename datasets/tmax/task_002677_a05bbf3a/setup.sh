#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/reference.fasta
>ref1
ATGCGTACGTAGCTAGCTAGCATCGATCGATCGACTAGCTAGCTAGCTAGCATCGATCG
EOF

    cat << 'EOF' > /home/user/candidates.txt
CGTAGCTAGC
ATCGATCGAT
GGGGGGGGGG
CTAGCATCGA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
