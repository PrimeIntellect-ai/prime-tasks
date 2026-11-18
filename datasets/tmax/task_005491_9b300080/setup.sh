#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import base64
import hmac
import hashlib
import json

os.makedirs('/home/user/audit_data', exist_ok=True)

# 1. Create the dummy ELF binary with the secret
secret_key = "s3cr3t99"

c_code = f"""
#include <stdio.h>
const char* key = "KEY_MATERIAL_{secret_key}";
int main() {{
    printf("Daemon running...\\n");
    return 0;
}}
"""
with open('/tmp/auth_daemon.c', 'w') as f:
    f.write(c_code)

os.system('gcc /tmp/auth_daemon.c -o /home/user/audit_data/auth_daemon')

# 2. Generate the requests.log
def encode_b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

def create_jwt(header, payload, secret=None):
    h_b64 = encode_b64url(json.dumps(header))
    p_b64 = encode_b64url(json.dumps(payload))
    msg = f"{h_b64}.{p_b64}"
    if secret:
        sig = hmac.new(secret.encode(), msg.encode(), hashlib.sha256).digest()
        sig_b64 = encode_b64url(sig)
        return f"{msg}.{sig_b64}"
    else:
        return f"{msg}."

# Admin PIN is 5678. MD5 = a7465913bc54df6cc12b5f6ceb1456a7
pin_hash = hashlib.md5(b"5678").hexdigest()

# Valid admin token
tok1 = create_jwt({"alg": "HS256", "typ": "JWT"}, {"user": "admin", "pin_hash": pin_hash}, secret_key)
# Valid user token
tok2 = create_jwt({"alg": "HS256", "typ": "JWT"}, {"user": "guest", "pin_hash": "d41d8cd98f00b204e9800998ecf8427e"}, secret_key)
# Forged admin token 1 (alg=none)
tok3 = create_jwt({"alg": "none", "typ": "JWT"}, {"user": "admin", "role": "superuser"})
# Forged admin token 2 (alg=None)
tok4 = create_jwt({"alg": "None", "typ": "JWT"}, {"user": "admin", "role": "superuser"})

http_template = """GET /api/data HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0
Cookie: session_token={token}
Accept: */*

"""

with open('/home/user/audit_data/requests.log', 'w') as f:
    f.write(http_template.format(token=tok1))
    f.write(http_template.format(token=tok2))
    f.write(http_template.format(token=tok3))
    f.write(http_template.format(token=tok4))

    # Add a few without cookies or different cookies
    f.write("GET /index.html HTTP/1.1\nHost: example.com\n\n\n")
    f.write("GET /api/admin HTTP/1.1\nHost: example.com\nCookie: session_token=" + create_jwt({"alg": "NONE"}, {"user": "system"}) + "\n\n\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py /tmp/auth_daemon.c

    chmod -R 777 /home/user
