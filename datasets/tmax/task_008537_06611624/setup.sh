#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_requests

    cat << 'EOF' > /home/user/signatures.txt
union select
<script>
/etc/passwd
EOF

    cat << 'EOF' > /tmp/req1.raw
POST /api/webhook HTTP/1.1
Host: example.com
Authorization: Bearer 1234567890abcdef
Content-Type: application/json

{"user":"admin", "action":"login"}
EOF
    base64 -w 0 /tmp/req1.raw > /home/user/incoming_requests/req1.b64

    cat << 'EOF' > /tmp/req2.raw
POST /api/webhook HTTP/1.1
Host: example.com
Authorization: Bearer 1234567890abcde
Content-Type: application/json

{"user":"guest", "action":"view"}
EOF
    base64 -w 0 /tmp/req2.raw > /home/user/incoming_requests/req2.b64

    cat << 'EOF' > /tmp/req3.raw
POST /api/webhook HTTP/1.1
Host: example.com
Authorization: Bearer aaaaaabbbbbbcccc
Content-Type: application/json

{"user":"admin' union select * from users--", "action":"login"}
EOF
    base64 -w 0 /tmp/req3.raw > /home/user/incoming_requests/req3.b64

    cat << 'EOF' > /tmp/req4.raw
POST /api/webhook HTTP/1.1
Host: example.com
Authorization: Bearer AAAAAABBBBBBCCCC
Content-Type: application/json

{"user":"<script>alert(1)</script>", "action":"login"}
EOF
    base64 -w 0 /tmp/req4.raw > /home/user/incoming_requests/req4.b64

    chmod -R 777 /home/user
