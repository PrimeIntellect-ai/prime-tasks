#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_logs.txt
2023-10-01T10:00:00Z 192.168.1.10 GET /login?return_url=%2Fdashboard HTTP/1.1
2023-10-01T10:02:00Z 10.0.0.4 GET /login?return_url=https%3A%2F%2Fevil.com%2Fprofile%3Fuser%3Dtest HTTP/1.1
2023-10-01T10:05:00Z 10.0.0.5 GET /login?return_url=https%3A%2F%2Fevil.com%2Fadmin%2Fescalate%3Fuser%3Dtest HTTP/1.1
2023-10-01T10:10:00Z 172.16.0.2 GET /login?return_url=http%3A%2F%2Finternal.corp%2Fadmin%2Fsettings HTTP/1.1
2023-10-01T10:15:00Z 10.0.0.9 GET /login?return_url=https%3A%2F%2Fattacker.net%2Fsu%2Froot HTTP/1.1
EOF

    cat << 'EOF' > /home/user/csp.txt
Content-Security-Policy: default-src 'self'; script-src 'self' 'strict-dynamic' https://trusted.cdn.com; object-src 'none';
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
