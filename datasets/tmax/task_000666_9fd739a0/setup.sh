#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip sed findutils gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/docs_raw/api
    mkdir -p /home/user/docs_raw/guides

    cat << 'EOF' > /home/user/docs_raw/api/endpoints.md
# API Endpoints
These are the endpoints.
Copyright 2018 Acme Corp
EOF

    cat << 'EOF' > /home/user/docs_raw/guides/setup.txt
Setup Guide
Please follow these steps.
Copyright 2018 Acme Corp
EOF

    cat << 'EOF' > /home/user/docs_raw/readme.md
# Main Readme
Welcome to the docs.
Copyright 2018 Acme Corp. All rights reserved.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
