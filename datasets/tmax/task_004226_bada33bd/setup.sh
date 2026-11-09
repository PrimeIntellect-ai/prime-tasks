#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/certs
    mkdir -p /home/user/audit_trail

    cat << 'EOF' > /home/user/raw_logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /checkout?card=4555666677778888&item=shoes HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:13:56:10 +0000] "POST /api/data?format=json&api_key=AKIAIOSFODNN7EXAMPLE HTTP/1.1" 201 512
172.16.0.2 - - [10/Oct/2023:13:58:22 +0000] "GET /status?api_key=SECRET_999&card=1234&user=admin HTTP/1.1" 200 128
EOF

    echo "super_secret_audit_passphrase_2023" > /home/user/certs/audit_key.pem

    chown -R user:user /home/user/raw_logs /home/user/certs /home/user/audit_trail
    chmod -R 777 /home/user
