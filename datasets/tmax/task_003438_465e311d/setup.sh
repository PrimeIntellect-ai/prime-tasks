#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/evidence
    cd /home/user/evidence

    cat << 'EOF' > http_traffic.log
GET /index.html HTTP/1.1
Host: internal.app
Cookie: session_id=safetoken123
User-Agent: Mozilla/5.0

POST /login HTTP/1.1
Host: internal.app
Cookie: session_id=malicious_token_8891
Content-Type: application/x-www-form-urlencoded
Content-Length: 32

username=admin' OR 1=1 --&pass=1
EOF

    cat << 'EOF' > wordlist.txt
password123
qwerty
admin123
letmein
autumn2023
winter2024
EOF

    python3 -c 'import crypt; print("admin:" + crypt.crypt("winter2024", "$6$somesalt$") + ":19000:0:99999:7:::")' > shadow.bak
    echo "daemon:*:19000:0:99999:7:::" >> shadow.bak

    openssl req -x509 -newkey rsa:2048 -keyout /dev/null -out server.pem -days 365 -nodes -subj "/C=US/ST=NY/L=NYC/O=SecCorp/CN=Internal-Root-CA" 2>/dev/null

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/evidence
    chmod -R 777 /home/user
