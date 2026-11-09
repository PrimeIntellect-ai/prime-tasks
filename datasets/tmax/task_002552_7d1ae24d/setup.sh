#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/seqA.txt
ACGT
ATAT
CGCG
ACGT
ACGT
EOF

    cat << 'EOF' > /home/user/seqB.txt
GGCC
CGCG
ACGT
CCCG
CCGC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
