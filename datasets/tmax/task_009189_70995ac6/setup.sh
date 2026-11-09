#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/audit_data/certs /home/user/audit_data/responses

    # Create Service Alpha Cert
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key_alpha.pem -out /home/user/audit_data/certs/service_alpha.pem -days 3650 -nodes -subj "/C=US/ST=State/L=City/O=Internal Security/CN=Internal Root CA"

    # Create Service Beta Cert
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key_beta.pem -out /home/user/audit_data/certs/service_beta.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Untrusted Corp/CN=Untrusted Corp"

    # Create Service Alpha Response
    cat << 'EOF' > /home/user/audit_data/responses/service_alpha.txt
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'
X-Frame-Options: DENY
Set-Cookie: session_id=abc123xyz; Secure; HttpOnly
Set-Cookie: tracking_id=987654; Secure; HttpOnly
Content-Type: text/html

<html><body>Alpha</body></html>
EOF

    # Create Service Beta Response
    cat << 'EOF' > /home/user/audit_data/responses/service_beta.txt
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Strict-Transport-Security: max-age=31536000
Set-Cookie: auth_token=jwt_token_here; HttpOnly
Content-Type: application/json

{"status": "ok"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
