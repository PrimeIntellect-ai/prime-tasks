#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bin
mkdir -p /home/user/evidence
mkdir -p /home/user/attacker_tools
mkdir -p /home/user/token_forge

touch /home/user/bin/sys_monitor
touch /home/user/bin/net_check
touch /home/user/bin/backup_util
touch /home/user/bin/cleaner
touch /home/user/bin/log_rotate

cat << 'EOF' > /home/user/evidence/server.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 1024
10.10.5.5 - - [10/Oct/2023:13:56:01 -0700] "GET /hidden/payload HTTP/1.1" 403 128
192.168.1.15 - - [10/Oct/2023:13:57:22 -0700] "POST /api/login HTTP/1.1" 401 512
172.16.0.4 - - [10/Oct/2023:13:58:10 -0700] "GET /hidden/payload HTTP/1.1" 200 4321
10.10.5.5 - - [10/Oct/2023:13:59:00 -0700] "GET /admin/dashboard HTTP/1.1" 404 256
EOF

cat << 'EOF' > /home/user/attacker_tools/crypto_spec.txt
// Attacker token generation spec
// Token format: {payload}.{hmac_sha256(payload, key)}
// Payload format: "IP:{ip}:EXP:{exp}"
// Key: "F0r3ns1csK3y!"
EOF

chown -R user:user /home/user

chmod -R 777 /home/user
chmod 755 /home/user/bin/*
chmod 4755 /home/user/bin/backup_util
