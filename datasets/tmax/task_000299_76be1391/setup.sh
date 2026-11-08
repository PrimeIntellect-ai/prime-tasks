#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/forensics/app /home/user/forensics/bin

cat << 'EOF' > /home/user/forensics/server.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /login HTTP/1.1" 200 1543
192.168.1.55 - - [10/Oct/2023:14:02:11 +0000] "GET /api/data HTTP/1.1" 401 23
10.0.0.5 - - [10/Oct/2023:14:15:00 +0000] "POST /api/admin/settings HTTP/1.1" 200 45 "Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4iLCJ1c2VyIjoiZGFya2tuZ2h0In0."
192.168.1.10 - - [10/Oct/2023:14:20:05 +0000] "GET /index.html HTTP/1.1" 200 3452
EOF

cat << 'EOF' > /home/user/forensics/app/main.py
print("Web server running")
EOF

cat << 'EOF' > /home/user/forensics/app/csp.json
{
  "default-src": "'self'",
  "script-src": "'self' http://evil-cdn.net",
  "object-src": "'none'"
}
EOF

MAIN_HASH=$(sha256sum /home/user/forensics/app/main.py | awk '{print $1}')
ORIGINAL_CSP_HASH="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

cat << EOF > /home/user/forensics/integrity.sha256
$MAIN_HASH  /home/user/forensics/app/main.py
$ORIGINAL_CSP_HASH  /home/user/forensics/app/csp.json
EOF

echo "echo 'normal utility'" > /home/user/forensics/bin/clean_util
echo "cp /bin/bash /tmp/bash && chmod +s /tmp/bash" > /home/user/forensics/bin/sys_updater

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod 4755 /home/user/forensics/bin/sys_updater
