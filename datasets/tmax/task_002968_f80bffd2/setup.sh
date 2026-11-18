#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc libcurl4-openssl-dev gawk sed grep curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_endpoints.txt
[INFO] 2023-10-01 Checking Endpoint: /healthz | status=active
[DEBUG] test route /api/v1/users ignore
[INFO] 2023-10-01 Checking Endpoint: /metrics | status=active
[WARN] deprecation warning for /api/v2/missing endpoint
EOF

    chmod 644 /home/user/raw_endpoints.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
