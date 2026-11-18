#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    # Create the benign binary (with a known sum % 256)
    cat << 'EOF' > /home/user/benign.bin
This is a fake benign binary used for EDR checksum simulation.
It contains some random data to generate a specific 8-bit checksum.
EOF

    # Create the HTTP request file
    cat << 'EOF' > /home/user/http_req.txt
GET /api/v1/profile HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0
Accept: */*
Cookie: session_id=abc123xyz; auth_token=S3cr3t_RedTeam_P4yL0ad; user_prefs=darkmode
Connection: close

EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
