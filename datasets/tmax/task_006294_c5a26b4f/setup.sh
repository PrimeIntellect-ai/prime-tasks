#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/doc1.txt
Hello World! Data is great.
EOF

    cat << 'EOF' > /home/user/raw_data/doc2.txt
World of data science. Let's tokenize it!
EOF

    cat << 'EOF' > /home/user/raw_data/doc3.txt
Data... data... DATA! Science is fun.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
