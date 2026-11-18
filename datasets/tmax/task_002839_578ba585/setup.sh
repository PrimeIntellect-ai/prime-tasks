#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl jq curl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/evidence

# 1. Create the rogue certificate
openssl req -x509 -newkey rsa:2048 -keyout /home/user/evidence/rogue.key -out /home/user/evidence/rogue.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=RogueCorp/CN=rogue.local"

# 2. Create the wordlist
cat << 'EOF' > /home/user/evidence/wordlist.txt
password123
admin
qwerty
secret
letmein
sup3rs3cr3t
winter2023
charlie
EOF

# 3. Create the JWT token
HEADER="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
PAYLOAD="eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoic3lzdGVtIn0"
SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -hmac "sup3rs3cr3t" -binary | base64 | tr -d '=' | tr '/+' '_-')
TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

# 4. Create the access.log
cat << EOF > /home/user/evidence/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "Authorization: Bearer eyJhb..."
10.0.0.5 - - [10/Oct/2023:13:56:10 +0000] "GET /api/users HTTP/1.1" 401 200 "-" "curl/7.68.0" "Authorization: Bearer invalidtoken"
172.16.0.42 - - [10/Oct/2023:13:58:22 +0000] "GET /api/files?path=../../../../etc/passwd HTTP/1.1" 200 1488 "-" "python-requests/2.25.1" "Authorization: Bearer ${TOKEN}"
192.168.1.15 - - [10/Oct/2023:13:59:01 +0000] "GET /images/logo.png HTTP/1.1" 200 4096 "-" "Mozilla/5.0" "-"
EOF

chown -R user:user /home/user/evidence
chmod -R 777 /home/user
