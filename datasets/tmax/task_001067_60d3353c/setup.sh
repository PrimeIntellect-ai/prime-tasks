#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.txt
Data science is an interdisciplinary academic field.
Data science uses statistics, scientific computing, and algorithms.
Algorithms are used in data science to extract insights from noisy data.
Machine learning is a part of data science.
Statistics and machine learning are related to data science.
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
