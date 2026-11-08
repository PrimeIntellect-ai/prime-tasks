#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis pyjwt

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/token_verifier
#!/usr/bin/env python3
import sys
import jwt
import base64
import json

def verify(token):
    try:
        parts = token.split('.')
        if len(parts) != 3:
            print("INVALID_FORMAT")
            return

        header_b64 = parts[0] + "=" * ((4 - len(parts[0]) % 4) % 4)
        try:
            header_json = base64.urlsafe_b64decode(header_b64).decode('utf-8')
            header = json.loads(header_json)
        except Exception:
            print("INVALID_FORMAT")
            return

        if header.get("alg") != "HS256":
            print("UNSUPPORTED_ALG")
            return

        jwt.decode(token, "secret_key_123", algorithms=["HS256"])
        print("VALID")
    except jwt.exceptions.InvalidSignatureError:
        print("INVALID_SIGNATURE")
    except Exception:
        print("INVALID_FORMAT")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        verify(sys.argv[1])
    else:
        print("INVALID_FORMAT")
EOF
    chmod +x /opt/oracle/token_verifier

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/auth.py
import sys
import base64
import json

def verify_token(token_str):
    parts = token_str.split('.')
    if len(parts) != 3:
        print("INVALID_FORMAT")
        return

    header_b64 = parts[0] + "=" * ((4 - len(parts[0]) % 4) % 4)
    try:
        header = json.loads(base64.urlsafe_b64decode(header_b64).decode())
    except:
        print("INVALID_FORMAT")
        return

    if header.get("alg") == "none":
        print("VALID")
        return

    print("INVALID_SIGNATURE")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        verify_token(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/app/worker.py
import redis
import time
from config import REDIS_HOST, REDIS_PORT

def main():
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)
    while True:
        try:
            msg = r.lpop('log_queue')
            if msg:
                text = msg.decode('utf-8')
                with open('/home/user/app/secure_logs.txt', 'a') as f:
                    f.write(text + '\n')
            time.sleep(1)
        except Exception:
            time.sleep(1)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
server {
    listen 9999;
    location / {
        proxy_pass http://127.0.0.1:1111;
    }
}
EOF

    cat << 'EOF' > /home/user/app/config.py
REDIS_HOST = '127.0.0.1'
REDIS_PORT = 1111
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
