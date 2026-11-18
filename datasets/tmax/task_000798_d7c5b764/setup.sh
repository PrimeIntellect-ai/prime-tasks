#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/traffic.log
[2023-10-27 10:00:01] GET /index.html HTTP/1.1
[2023-10-27 10:00:05] GET /search?data=PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg== HTTP/1.1
[2023-10-27 10:01:12] GET /search?data=PHNjcmlwdCBzcmM9Imh0dHBzOi8vY2RuLnZ1bG5lcmFibGUuY29tL2pzb25wP2NhbGxiYWNrPWFsZXJ0KGRvY3VtZW50LmNvb2tpZSkiPjwvc2NyaXB0Pg== HTTP/1.1
[2023-10-27 10:02:00] GET /search?data=PGltZyBzcmM9eCBvbmVycm9yPWFsZXJ0KDEpPg== HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
