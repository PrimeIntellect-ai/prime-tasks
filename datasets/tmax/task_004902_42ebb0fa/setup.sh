#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils grep gawk
    pip3 install pytest

    mkdir -p /home/user/http_logs

    cat << 'EOF' > /home/user/http_logs/log_01.txt
HTTP/1.1 302 Found
Location: https://internal-app.local/dashboard
Set-Cookie: session_id=abc123safe; Secure; HttpOnly
Connection: close
EOF

    cat << 'EOF' > /home/user/http_logs/log_02.txt
HTTP/1.1 302 Found
Location: http://malicious-login.com/steal?redirect=true
Set-Cookie: session_id=xyz890leaked; Secure; HttpOnly
Connection: close
EOF

    cat << 'EOF' > /home/user/http_logs/log_03.txt
HTTP/1.1 200 OK
Content-Type: text/html
Set-Cookie: session_id=111122223333; Secure; HttpOnly
Connection: close
EOF

    cat << 'EOF' > /home/user/new_keys.pem
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQ...
-----END PRIVATE KEY-----
EOF

    cd /home/user
    sha256sum new_keys.pem > keys.checksum

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
