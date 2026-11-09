#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip supervisor zip unzip
    pip3 install pytest

    mkdir -p /home/user/mail/incoming
    mkdir -p /home/user/mail/sanitized
    mkdir -p /home/user/mail/processed
    mkdir -p /home/user/mail/backup

    cat << 'EOF' > /home/user/mail/incoming/msg1.eml
From: alice@example.com
To: list@example.com
Subject: Test message 1
X-Internal-Route: 10.0.0.5

Hello world!
EOF

    cat << 'EOF' > /home/user/mail/incoming/msg2.eml
From: bob@example.com
To: list@example.com
Subject: Test message 2
X-Internal-Route: 192.168.1.10
X-Safe-Header: true

This is the second message.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
