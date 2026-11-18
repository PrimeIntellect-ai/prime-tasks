#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest pyjwt

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_investigation/uploads
    mkdir -p /home/user/audit_investigation/system

    echo -n "c0mpl1anc3_s3cr3t_k3y" > /home/user/audit_investigation/jwt_secret.txt

    cat << 'EOF' > /tmp/gen_tokens.py
import jwt
import datetime

secret = "c0mpl1anc3_s3cr3t_k3y"
now = datetime.datetime.utcnow()

token1 = jwt.encode({"user": "guest", "jti": "auth-1111", "exp": now + datetime.timedelta(days=365)}, secret, algorithm="HS256")
token2 = jwt.encode({"user": "admin", "jti": "auth-2222", "exp": now - datetime.timedelta(days=365)}, secret, algorithm="HS256")
token3 = jwt.encode({"user": "admin", "jti": "auth-8472", "exp": now + datetime.timedelta(days=365)}, secret, algorithm="HS256")

with open("/home/user/audit_investigation/captured_tokens.txt", "w") as f:
    f.write(f"{token1}\n{token2}\n{token3}\n")
EOF
    python3 /tmp/gen_tokens.py
    rm /tmp/gen_tokens.py

    cd /tmp
    echo -n "NDU1NjQ5NDQ0NTRlNDM0NTVmNDY0ZjU1NGU0NDVmNDM1MjQ5NTQ0OTQzNDE0YzVmNTM1OTUzNTQ0NTRkNWY0MzRmNGQ1MDUyNGY0ZDQ5NTM0NQ==" > payload.txt
    zip -P 6291 /home/user/audit_investigation/system/backup.zip payload.txt
    rm payload.txt

    chmod -R 777 /home/user
