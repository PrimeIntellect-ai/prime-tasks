#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/app_config.json
{
  "app_name": "VulnerableApp",
  "version": "1.2.4",
  "xor_key": "responder_key_2024"
}
EOF

cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2024:13:55:36 +0000] "GET /api/data HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiZ3Vlc3QifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
192.168.1.55 - - [10/Oct/2024:14:02:11 +0000] "POST /api/settings HTTP/1.1" 200 512 "-" "curl/7.68.0" "Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJlbmNyeXB0ZWRfZGF0YSI6Ik5Rd2JGeEJRWFVjSUZ3MVhYRnBRUkJRUVZWSWFCUTVlVDF4WFd4QUdYRkZERXhRTVcxMGZIeGxRVTF3SUZ3dFJTUmRYWHhFYVhWTUpGQVljVlYxRyJ9."
192.168.1.12 - - [10/Oct/2024:14:15:00 +0000] "GET /api/profile HTTP/1.1" 401 23 "-" "PostmanRuntime/7.28.4" "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdCJ9.invalid_signature_here"
EOF

chmod -R 777 /home/user
