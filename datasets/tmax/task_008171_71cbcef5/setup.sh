#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest

    mkdir -p /home/user/docs_source/api
    mkdir -p /home/user/docs_source/setup

    cat << 'EOF' > /home/user/docs_source/intro.md
# Introduction
Welcome to the official documentation for ProductX-v1.0-alpha.
This guide will help you get started with ProductX-v1.0-alpha.
EOF

    cat << 'EOF' > /home/user/docs_source/api/auth.md
# Authentication
To authenticate with ProductX-v1.0-alpha, use a Bearer token.
ProductX-v1.0-alpha supports OAuth2.
EOF

    cat << 'EOF' > /home/user/docs_source/setup/install.md
# Installation
Run the installer for ProductX-v1.0-alpha.
Make sure your system meets the requirements for ProductX-v1.0-alpha!
EOF

    cat << 'EOF' > /home/user/docs_source/setup/notes.txt
This is a plain text file, not a markdown file. It mentions ProductX-v1.0-alpha but should NOT be modified or included in the manifest.
EOF

    cd /home/user/docs_source
    tar -czf /home/user/docs_archive.tar.gz *
    cd /home/user
    rm -rf /home/user/docs_source

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
