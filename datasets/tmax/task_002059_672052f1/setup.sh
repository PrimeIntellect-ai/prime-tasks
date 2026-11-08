#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk parallel
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs

cat << 'EOF' > /home/user/logs/node_1.log
[2023-11-15T08:34:12Z] 192.168.12.45 GET /Api/v1/Users?id=5 200
[2023-11-15T08:39:59Z] 192.168.12.45 GET /API/V1/users?id=5 200
[2023-11-15T08:41:02Z] 10.0.0.12 POST /login 201
EOF

cat << 'EOF' > /home/user/logs/node_2.log
[2023-11-15T08:31:05Z] 192.168.12.22 GET /api/v1/users 200
[2023-11-15T08:45:10Z] 10.0.0.12 POST /Login 401
EOF

cat << 'EOF' > /home/user/logs/node_3.log
[2023-11-15T08:37:12Z] 192.168.12.200 GET /Api/v1/Users?limit=10 200
[2023-11-15T08:49:59Z] 172.16.5.5 GET /healthcheck 200
EOF

cat << 'EOF' > /home/user/logs/node_4.log
[2023-11-15T08:35:12Z] 192.168.12.99 GET /Api/v1/Users?limit=10 200
EOF

chown -R user:user /home/user/logs
chmod -R 777 /home/user
