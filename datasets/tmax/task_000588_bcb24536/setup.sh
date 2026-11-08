#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    # Create the c2_decoder binary
    mkdir -p /app
    cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>

int main() {
    FILE *fp = popen("base64 -d", "r");
    if (!fp) return 1;
    int c;
    while ((c = fgetc(fp)) != EOF) {
        putchar(c ^ 0x5A);
    }
    pclose(fp);
    return 0;
}
EOF
    gcc -O2 -o /app/c2_decoder /tmp/decoder.c
    strip /app/c2_decoder
    chmod +x /app/c2_decoder
    rm /tmp/decoder.c

    # Generate the corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import base64
import os

def obfuscate(text):
    xored = bytes([c ^ 0x5A for c in text.encode('utf-8')])
    return base64.b64encode(xored).decode('utf-8')

clean = [
    "GET /index.html HTTP/1.1\nHost: example.com",
    "POST /login HTTP/1.1\nHost: example.com\n\nuser=admin&pass=1234",
    "GET /images/logo.png HTTP/1.1\nHost: example.com"
]

evil = [
    "GET /search?q=<script>alert(1)</script> HTTP/1.1\nHost: example.com",
    "POST /login HTTP/1.1\nHost: example.com\n\nuser=admin' OR '1'='1",
    "GET /profile?id=1; DROP TABLE users HTTP/1.1\nHost: example.com",
    "GET /?q=javascript:alert(1) HTTP/1.1\nHost: example.com",
    "GET /?q=UNION SELECT username, password FROM users HTTP/1.1\nHost: example.com"
]

os.makedirs("/var/test_corpus/clean", exist_ok=True)
os.makedirs("/var/test_corpus/evil", exist_ok=True)

for i, c in enumerate(clean):
    with open(f"/var/test_corpus/clean/{i}.txt", "w") as f:
        f.write(obfuscate(c))

for i, e in enumerate(evil):
    with open(f"/var/test_corpus/evil/{i}.txt", "w") as f:
        f.write(obfuscate(e))
EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
