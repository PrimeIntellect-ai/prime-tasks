#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_assets
    mkdir -p /home/user/clean_docs

    # Create binary and text files
    echo -n "Binary content A" > /home/user/raw_assets/img_101.bin
    echo -n "Binary content B" > /home/user/raw_assets/img_102.bin
    echo -n "Binary content C" > /home/user/raw_assets/img_103.bin
    echo "Markdown text A" > /home/user/raw_assets/doc_101.md
    echo "Markdown text B" > /home/user/raw_assets/doc_102.md
    echo "Markdown text C" > /home/user/raw_assets/doc_103.md

    # Create the log file
    cat << 'EOF' > /home/user/cms_export.log
=== RECORD START ===
DocID: 101
Title: System Setup Guide
TextFile: doc_101.md
AssetFile: img_101.bin
Status: PUBLISHED
=== RECORD END ===
=== RECORD START ===
DocID: 102
Title: Internal Draft API
TextFile: doc_102.md
AssetFile: img_102.bin
Status: DRAFT
=== RECORD END ===
=== RECORD START ===
DocID: 103
Title: User Manual v2
TextFile: doc_103.md
AssetFile: img_103.bin
Status: PUBLISHED
=== RECORD END ===
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
