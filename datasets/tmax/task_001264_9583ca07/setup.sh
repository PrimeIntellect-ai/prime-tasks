#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/http_dump.txt
HTTP/1.1 200 OK
Date: Mon, 23 May 2023 22:38:34 GMT
Set-Cookie: session=xyz890abc; HttpOnly
Authorization: Bearer a1b2c3d4e5f6
X-Crypto-Payload: 1234567890abcdef1234567890abcdef
Set-Cookie: tracking=foo; Secure; HttpOnly
X-Crypto-Payload: abcdef1234567890deadbeefcafebabe
Set-Cookie: session=vuln456; Path=/
X-Crypto-Payload: 0000000000000000111111111111111122222222222222220000000000000000
Content-Type: application/json
Authorization: Basic dXNlcjpwYXNz
Set-Cookie: prefs=darkmode; Secure
EOF

    chmod -R 777 /home/user
