#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip logrotate socat curl gawk sed grep
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
cat << 'EOF' > /home/user/logs/api.log
INFO 2023-10-01T10:00:00 [API] GET /users 120ms
ERROR 2023-10-01T10:00:01 [API] POST /data 450ms
INFO 2023-10-01T10:00:02 [DB] query 50ms
INFO 2023-10-01T10:00:03 [API] GET /users 130ms
ERROR 2023-10-01T10:00:04 [API] GET /users 500ms
EOF

for i in $(seq 1 20); do cat /home/user/logs/api.log >> /home/user/logs/api_temp.log; done
mv /home/user/logs/api_temp.log /home/user/logs/api.log

mkdir -p /home/user/server
echo "OK" > /home/user/server/health

chmod -R 777 /home/user
