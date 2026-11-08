#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libssl-dev binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the token tool binary
    cat << 'EOF' > /tmp/token_tool.c
#include <stdio.h>
int main() {
    const char* key = "S3cr3tK3y_Rotat1on_2023_HMAC_STR";
    printf("Legacy token tool. Key is loaded.\n");
    return 0;
}
EOF
    gcc -O2 /tmp/token_tool.c -o /app/token_tool
    strip /app/token_tool
    chmod +x /app/token_tool

    # Generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import base64
import hmac
import hashlib
import json
import os

key = b"S3cr3tK3y_Rotat1on_2023_HMAC_STR"

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')

def make_token(header, payload, sign_key=None, empty_sig=False):
    h = b64url(json.dumps(header))
    p = b64url(json.dumps(payload))
    msg = f"{h}.{p}".encode()
    if empty_sig:
        return f"{h}.{p}."
    if sign_key is None:
        return f"{h}.{p}"
    sig = hmac.new(sign_key, msg, hashlib.sha256).digest()
    return f"{h}.{p}.{b64url(sig)}"

def write_req(path, token=None):
    with open(path, 'w') as f:
        f.write("GET /api/data HTTP/1.1\n")
        f.write("Host: example.com\n")
        if token is not None:
            f.write(f"Authorization: Bearer {token}\n")
        f.write("\n")

# Clean
write_req("/app/corpus/clean/req1.txt", make_token({"alg": "HS256", "typ": "PTK"}, {"user": "admin"}, key))
write_req("/app/corpus/clean/req2.txt", make_token({"alg": "HS256", "typ": "PTK"}, {"user": "guest"}, key))

# Evil
valid_token = make_token({"alg": "HS256", "typ": "PTK"}, {"user": "guest"}, key)
parts = valid_token.split('.')
evil_payload = b64url(json.dumps({"user": "admin"}))
write_req("/app/corpus/evil/req1.txt", f"{parts[0]}.{evil_payload}.{parts[2]}")
write_req("/app/corpus/evil/req2.txt", make_token({"alg": "none", "typ": "PTK"}, {"user": "admin"}, empty_sig=True))
write_req("/app/corpus/evil/req3.txt", make_token({"alg": "none", "typ": "PTK"}, {"user": "admin"}, b"random"))
write_req("/app/corpus/evil/req4.txt", None)
write_req("/app/corpus/evil/req5.txt", make_token({"alg": "HS256", "typ": "PTK"}, {"user": "admin"}))
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
