#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_docs
    cat << 'EOF' > /home/user/test_data.log
RECORD_START
Path: docs/intro.md
Title: Introduction Guide
RECORD_END

RECORD_START
Path: ../../../etc/shadow
Title: System Passwords
RECORD_END

RECORD_START
Path: docs/api/reference.md
Title: API Reference V2
RECORD_END

RECORD_START
Path: safe_dir/../malicious.sh
Title: Sneaky Script
RECORD_END

RECORD_START
Path: assets/logo.png
Title: Company Logo
RECORD_END
EOF

    chmod -R 777 /home/user
