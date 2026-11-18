#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/analyzer

    cat << 'EOF' > /home/user/traffic.log
GET /index.html HTTP/1.1
Host: example.com
Cookie: Session-Id=SecureSession999

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self'

GET /dashboard HTTP/1.1
Host: example.com
Cookie: Session-Id=VulnSession8472

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self' 'unsafe-inline'

GET /api/data HTTP/1.1
Host: example.com
Cookie: Session-Id=OtherSession111

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self'
EOF

    cat << 'EOF' > /home/user/cert.pem
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 123456789 (0x75bcd15)
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=US, ST=CA, O=VulnCorp, CN=VulnCorp_Root
        Validity
            Not Before: Jan  1 00:00:00 2023 GMT
            Not After : Dec 31 23:59:59 2025 GMT
        Subject: C=US, ST=CA, O=VulnCorp, CN=VulnCorp_Internal_CA
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
-----BEGIN CERTIFICATE-----
MIIB... (mock base64) ...
-----END CERTIFICATE-----
EOF

    cat << 'EOF' > /home/user/hashes.txt
47ca8f01b17d0966a3efb07b1c4b72611732c5fc6bc6bd810f69a6566c1bba4f
6d6c6e7552504287be122c60e340d04c000bd5b4c4fae857dddb3f7b88950fb2
EOF

    chmod -R 777 /home/user
