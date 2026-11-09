#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_raw/api/v1
    mkdir -p /home/user/docs_raw/api/v2
    mkdir -p /home/user/docs_raw/tutorials

    # File 1: Plain text, Draft
    cat << 'EOF' > /home/user/docs_raw/guide.md
Status: Draft
Title: Main Guide

This is a draft.
EOF

    # File 2: Gzipped text, Publish
    cat << 'EOF' > /tmp/endpoints.txt
Status: Publish
Title: Endpoints API v1

GET /api/v1/status
EOF
    gzip -c /tmp/endpoints.txt > /home/user/docs_raw/api/v1/endpoints.txt.gz

    # File 3: Gzipped text, Draft
    cat << 'EOF' > /tmp/auth.md
Status: Draft
Title: Auth API v2

OAuth2 implementation notes.
EOF
    gzip -c /tmp/auth.md > /home/user/docs_raw/api/v2/auth.md.gz

    # File 4: Plain text, Publish
    cat << 'EOF' > /home/user/docs_raw/tutorials/getting_started.md
Status: Publish
Title: Getting Started

Welcome to the documentation.
EOF

    chmod -R 777 /home/user
