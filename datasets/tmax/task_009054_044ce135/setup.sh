#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/routes.json
[
  {"service": "auth", "version": "1.0.0", "port": 8080},
  {"service": "auth", "version": "1.2.0", "port": 8081},
  {"service": "auth", "version": "1.3.0", "port": 8082},
  {"service": "auth", "version": "2.0.0", "port": 8083},
  {"service": "payment", "version": "1.1.0", "port": 9090},
  {"service": "payment", "version": "1.1.5", "port": 9091}
]
EOF

    cat << 'EOF' > /home/user/requests.log
1700000000 10.0.0.1 GET /api/auth/v1.2.5
1700000001 10.0.0.1 POST /api/auth/v1.2.5
1700000002 10.0.0.1 GET /api/auth/v1.3.5
1700000004 10.0.0.1 GET /api/auth/v1.1.0
1700000007 10.0.0.1 GET /api/auth/v1.2.0
1700000008 192.168.1.5 GET /api/payment/v1.1.4
1700000009 192.168.1.5 GET /api/payment/v1.1.6
1700000015 10.0.0.1 GET /api/auth/v2.1.0
1700000016 10.0.0.1 GET /api/auth/v0.9.0
EOF

    chmod -R 777 /home/user
