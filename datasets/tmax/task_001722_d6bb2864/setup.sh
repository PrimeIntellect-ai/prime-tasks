#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libssl-dev \
        espeak \
        ffmpeg

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the intercepted call audio
    espeak -w /app/intercepted_call.wav "We successfully dumped the legacy config. The secret salt for the HMAC token is OmegaDeltaNineNine."

    # Generate the corpora
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import hmac
import hashlib

salt = b"OmegaDeltaNineNine"

def get_hmac(url):
    return hmac.new(salt, url.encode(), hashlib.sha256).hexdigest()

def write_req(path, url, token=None, modify=False):
    if token is None:
        token = get_hmac(url)
    if modify:
        token = token[:-1] + ('a' if token[-1] != 'a' else 'b')
    req = f"GET / HTTP/1.1\r\nHost: example.com\r\nX-Redirect-URL: {url}\r\nX-Auth-Token: {token}\r\n\r\n"
    with open(path, "w") as f:
        f.write(req)

# Clean
write_req("/app/corpus/clean/req1.txt", "https://trusted.corp/dashboard")
write_req("/app/corpus/clean/req2.txt", "http://sso.trusted.corp/auth")
write_req("/app/corpus/clean/req3.txt", "https://app.trusted.corp/login")

# Evil
# 1. Missing token
with open("/app/corpus/evil/req1.txt", "w") as f:
    f.write("GET / HTTP/1.1\r\nHost: example.com\r\nX-Redirect-URL: https://trusted.corp/dashboard\r\n\r\n")

# 2. Invalid HMAC
write_req("/app/corpus/evil/req2.txt", "https://trusted.corp/dashboard", modify=True)

# 3. Valid HMAC but evil domain
write_req("/app/corpus/evil/req3.txt", "https://evil.com/login")
write_req("/app/corpus/evil/req4.txt", "https://trusted.corp.attacker.com/")
write_req("/app/corpus/evil/req5.txt", "http://not-trusted.corp/")
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
