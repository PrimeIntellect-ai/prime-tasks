#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/titles.txt
data structures in c
advanced c programming structures computing
intro to machine learning
machine learning and data analysis
data analysis with c programming structures
EOF

    chmod -R 777 /home/user
