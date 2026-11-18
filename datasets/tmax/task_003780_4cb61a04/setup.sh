#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/raw
    mkdir -p /home/user/extracted
    mkdir -p /home/user/extracted_zips
    mkdir -p /home/user/final_docs

    cat << 'EOF' > /home/user/raw/doc1.txt
Title: API v1
Status: [DRAFT]
This is the [DRAFT] documentation for API v1.
EOF

    cat << 'EOF' > /home/user/raw/doc2.txt
Title: Architecture
This architecture document is currently a [DRAFT].
EOF

    cat << 'EOF' > /home/user/raw/doc3.txt
[DRAFT] Release Notes
No major changes.
EOF

    cd /home/user/raw
    zip part1.zip doc1.txt doc2.txt
    zip part2.zip doc3.txt

    mkdir -p /home/user/archive_stage
    mv part1.zip part2.zip /home/user/archive_stage/
    cd /home/user/archive_stage
    tar -czf /home/user/raw_docs.tar.gz part1.zip part2.zip

    rm -rf /home/user/raw /home/user/archive_stage

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
