#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_docs.txt
==DOC==
Title: Introduction to System
Author: Alice Writer
Body:
This is the introduction.
It spans multiple lines.
==DOC==
Title: Installation Guide
Author: Bob Coder
Body:
Step 1: Download
Step 2: Install
Step 3: Profit!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
