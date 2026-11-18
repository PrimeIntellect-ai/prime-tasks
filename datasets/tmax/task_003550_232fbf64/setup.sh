#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/custom_hasher.py
import sys

def compute_hash(data):
    h = 0
    for b in data:
        h = (h + b) % 65536
    return h

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python custom_hasher.py <file>")
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        print(compute_hash(f.read()))
EOF

    cat << 'EOF' > /home/user/rules.txt
(?i)password=\w+
UNION\s+SELECT
admin_bypass
\.\./\.\./etc/passwd
EOF

    cat << 'EOF' > /home/user/traffic.log
GET /index.html HTTP/1.1
POST /login HTTP/1.1 body: Password=SecretUser123
GET /images/logo.png HTTP/1.1
GET /api/data?query=UNION SELECT * FROM users HTTP/1.1
GET /about_us.html HTTP/1.1
POST /upload HTTP/1.1 body: admin_bypass=true
GET /api/v1/health HTTP/1.1
GET /styles.css HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
