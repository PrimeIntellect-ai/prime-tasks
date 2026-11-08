#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.log
[2023-10-15T14:32:01Z] GET /api/v1/users 150
[2023-10-15T14:32:02Z] POST /api/v1/login 200
[2023-10-15T14:32:03Z] GET /api/v1/users 600
[2023-10-15T14:32:04Z] POST /api/v1/login 300
[2023-10-15T14:32:05Z] GET /api/v1/users 800
[2023-10-15T14:32:06Z] GET /api/v1/dashboard 100
[2023-10-15T14:32:07Z] POST /api/v1/login 400
[2023-10-15T14:32:08Z] GET /api/v1/users 200
[2023-10-15T14:32:09Z] GET /api/v1/users 700
[2023-10-15T14:32:10Z] POST /api/v1/login 900
[2023-10-15T14:32:11Z] POST /api/v1/login 400
EOF

    chmod -R 777 /home/user
