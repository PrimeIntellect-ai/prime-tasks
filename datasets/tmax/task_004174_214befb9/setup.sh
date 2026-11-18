#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs
    mkdir -p /home/user/output
    cat << 'EOF' > /home/user/app_logs/server.log
2023-11-01T08:12:00 INFO [payment.trusted.com] Connection established cc=1234-5678-1234-5678
2023-11-01T08:12:05 INFO [payment.trusted.com] CERT_VALIDATION_SUCCESS
2023-11-01T08:15:22 INFO [api.legacy-system.net] Initializing connection for user=admin cc=9999-8888-7777-6666
2023-11-01T08:15:23 ERROR [api.legacy-system.net] CERT_CHAIN_FAIL Expired certificate in chain
2023-11-01T08:15:25 INFO [api.legacy-system.net] Retrying connection without tls...
2023-11-01T08:20:01 INFO [analytics.tracker.io] Data sync cc=1111-2222-3333-4444
2023-11-01T08:20:02 ERROR [analytics.tracker.io] CERT_CHAIN_FAIL Self-signed cert
EOF
    chmod 644 /home/user/app_logs/server.log

    chmod -R 777 /home/user
