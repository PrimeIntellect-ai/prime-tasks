#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence/certs
    cd /home/user/evidence

    # Generate benign CA
    openssl req -x509 -newkey rsa:2048 -keyout benign_ca.key -out benign_ca.pem -days 365 -nodes -subj "/CN=Benign CA"
    # Generate rogue CA
    openssl req -x509 -newkey rsa:2048 -keyout rogue_ca.key -out rogue_ca.pem -days 365 -nodes -subj "/CN=Rogue CA"

    # Generate benign cert 1
    openssl req -newkey rsa:2048 -keyout certs/cert_1.key -out certs/cert_1.csr -nodes -subj "/CN=Benign Client 1"
    openssl x509 -req -in certs/cert_1.csr -CA benign_ca.pem -CAkey benign_ca.key -CAcreateserial -out certs/cert_1.pem -days 365

    # Generate benign cert 2
    openssl req -newkey rsa:2048 -keyout certs/cert_2.key -out certs/cert_2.csr -nodes -subj "/CN=Benign Client 2"
    openssl x509 -req -in certs/cert_2.csr -CA benign_ca.pem -CAkey benign_ca.key -CAcreateserial -out certs/cert_2.pem -days 365

    # Generate malicious cert 3 (Signed by Rogue CA)
    openssl req -newkey rsa:2048 -keyout certs/cert_3.key -out certs/cert_3.csr -nodes -subj "/CN=Attacker Client"
    openssl x509 -req -in certs/cert_3.csr -CA rogue_ca.pem -CAkey rogue_ca.key -CAcreateserial -out certs/cert_3.pem -days 365

    # Clean up private keys and CSRs to prevent confusion
    rm -f benign_ca.key rogue_ca.key certs/*.key certs/*.csr benign_ca.srl rogue_ca.srl benign_ca.pem

    cat << 'EOF' > /home/user/evidence/process_list.txt
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0 168156 11312 ?        Ss   Oct10   0:03 /sbin/init
user        1337  0.0  0.1  14236  5236 ?        S    10:01   0:00 bash ./exfiltrate.sh --target 192.168.1.50 --auth-token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.secret_signature_123 --port 443
user        1338  0.0  0.0  12344  3211 ?        S    10:01   0:00 sleep 60
EOF

    cat << 'EOF' > /home/user/evidence/web_access.log
192.168.1.10 - - [10/Oct/2023:10:00:01 +0000] "GET /api/data HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
192.168.1.10 - - [10/Oct/2023:10:00:05 +0000] "POST /api/upload HTTP/1.1" 200 512 "-" "curl/7.68.0" "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.secret_signature_123"
192.168.1.15 - - [10/Oct/2023:10:01:00 +0000] "GET /api/status HTTP/1.1" 401 256 "-" "python-requests/2.25.1"
192.168.1.50 - - [10/Oct/2023:10:02:15 +0000] "GET /api/admin HTTP/1.1" 200 2048 "-" "Custom-Agent" "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.secret_signature_123"
EOF

    chmod -R 777 /home/user
