#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/legacy_docs.txt
===FILE:Draft_v1_intro.md===
# Introduction
This is the new user guide.
===EOF===
===FILE:Draft_v4_api_reference.md===
# API Reference
Endpoints:
- /api/v1/users
- /api/v1/docs
===EOF===
===FILE:Draft_v12_troubleshooting.md===
# Troubleshooting
Have you tried turning it off and on again?
===EOF===
EOF
    chmod 644 /home/user/legacy_docs.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
