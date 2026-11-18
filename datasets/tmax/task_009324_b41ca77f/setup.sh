#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
[2023-10-24T12:00:00Z] 192.168.1.10 GET /api/users HTTP/1.1 200 45
[2023-10-24T12:00:01Z] 10.0.0.5 POST /api/login HTTP/1.1 200 120
[2023-10-24T12:00:02Z] 192.168.1.11 GET /api/users HTTP/1.1 500 200
[2023-10-24T12:00:03Z] 192.168.1.10 INVALID /api/users HTTP/1.1 200 50
[2023-10-24T12:00:04Z] 10.0.0.6 GET /api/data HTTP/1.1 200 -10
[2023-10-24T12:00:05Z] 10.0.0.7 GET /api/data HTTP/1.1 200 30
[2023-10-24T12:00:06Z] malformed line here missing fields
[2023-10-24T12:00:07Z] 192.168.1.12 GET /api/users HTTP/1.1 200 55
[2023-10-24T12:00:08Z] 10.0.0.8 PUT /api/data HTTP/1.1 201 40
[2023-10-24T12:00:09Z] 10.0.0.9 DELETE /api/old HTTP/1.1 204 15
[2023-10-24T12:00:10Z] 10.0.0.10 GET /api/users HTTP/1.1 xyz 100
EOF

    chmod -R 777 /home/user
