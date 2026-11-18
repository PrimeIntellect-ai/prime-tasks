#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_server.log
[12/Oct/2023:14:32:01 +0000] "GET /API/v1/users?email=alice.smith@example.com HTTP/1.1" 200 1024 IP: 192.168.1.50
[2023-10-12T14:35:10Z] "POST /API/V1/PAYMENTS HTTP/1.1" 201 512 IP: 10.0.0.5 CC: 1234-5678-9012-3456 User: bob_jones@domain.co.uk
[13/Oct/2023:09:15:00 +0000] "PUT /Secure/Vault/data HTTP/1.0" 403 0 IP: 172.16.254.1 SSN: 999-88-7777 and email charlie@hackers.org
[2023-10-14T00:00:01Z] "GET /health_check HTTP/1.1" 200 42 IP: 127.0.0.1
EOF

    chmod -R 777 /home/user
