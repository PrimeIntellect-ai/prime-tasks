#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_audit

    # Create OpenSSL config for SANs
    cat << 'EOF' > /tmp/openssl.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = SanFrancisco
O = InsecureApp
CN = prod.internal.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = prod.internal.local
DNS.2 = beta.internal.local
DNS.3 = staging-v2.internal.local
EOF

    # Generate the certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /tmp/server.key \
        -out /home/user/api_audit/server.crt \
        -config /tmp/openssl.cnf -extensions v3_req 2>/dev/null

    rm /tmp/server.key /tmp/openssl.cnf

    # Create the traffic log
    cat << 'EOF' > /home/user/api_audit/traffic.log
GET /api/v1/health HTTP/1.1
Host: prod.internal.local
User-Agent: curl/7.68.0
Accept: */*

POST /api/v1/data HTTP/1.1
Host: staging-v2.internal.local
User-Agent: Mozilla/5.0
Cookie: session_auth=dXNlcjF8MTY4MDAwMDAwMHxhMjIzN2E2YjRjMTA3ZTNlYTJkZDVhYmY3MzQ0MTlhZA==
X-Debug-Secret: B3ta_Stag1ng_S3cr3t
Accept: application/json

GET /api/v1/users HTTP/1.1
Host: beta.internal.local
User-Agent: Mozilla/5.0
Cookie: session_auth=someothercookie==
EOF

    chown -R user:user /home/user/api_audit
    chmod -R 777 /home/user
