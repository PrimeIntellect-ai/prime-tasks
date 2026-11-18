#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence/certs

    # Generate legitimate and rogue certificates
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/k1.pem -out /home/user/evidence/certs/site.crt -days 365 -nodes -subj "/CN=mywebsite.com" 2>/dev/null
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/k2.pem -out /home/user/evidence/certs/rogue.crt -days 365 -nodes -subj "/CN=exfil.evil.net" 2>/dev/null
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/k3.pem -out /home/user/evidence/certs/backup.crt -days 365 -nodes -subj "/CN=backup.mywebsite.com" 2>/dev/null

    # Create the server log file
    cat << 'EOF' > /home/user/evidence/server.log
[INFO] GET /index.html
[INFO] Header: Content-Security-Policy: default-src 'self';
[INFO] Payload: {"user": "guest", "cc": "5555666677778888"}
[INFO] GET /admin.html
[INFO] Header: Content-Security-Policy: default-src 'self'; report-uri https://exfil.evil.net/log
[INFO] Payload: {"user": "admin", "action": "payment", "cc": "4111-2222-3333-4444", "cvv": "123", "secondary_cc": "1111222233334444"}
[INFO] GET /about.html
[INFO] Header: Content-Security-Policy: default-src 'self';
[INFO] Payload: {"user": "anonymous", "status": "viewing"}
EOF

    chown -R user:user /home/user/evidence
    chmod -R 777 /home/user
