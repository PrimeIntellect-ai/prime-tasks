#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user/incoming
    cd /home/user/incoming

    # Create raw docs
    mkdir -p raw_docs
    # File 1: Valid (>50 bytes)
    printf "This is a valid engineering document with sufficient content to pass the filter.\n" > raw_docs/doc_a1.md
    # File 2: Invalid (<=50 bytes)
    printf "Too short.\n" > raw_docs/doc_b2.md
    # File 3: Valid (>50 bytes)
    printf "Marketing guidelines for Q3. Includes brand colors and typography specs.\n" > raw_docs/doc_c3.md
    # File 4: Valid (>50 bytes) but not in CSV
    printf "Unknown document with lots of text but no metadata mapping.\n" > raw_docs/doc_d4.md

    # Zip the raw docs
    zip -r raw_docs.zip raw_docs/

    # Create metadata.csv
    cat << 'EOF' > metadata.csv
doc_a1.md,Engineering,API_V2_Specs,4
doc_b2.md,HR,Leave_Policy,1
doc_c3.md,Marketing,Brand_Guide,2
EOF

    # Tar it up
    tar -czf legacy_docs.tar.gz raw_docs.zip metadata.csv

    # Cleanup intermediate files to leave only the tarball
    rm -rf raw_docs raw_docs.zip metadata.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
