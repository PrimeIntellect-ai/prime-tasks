#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng zip
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak-ng -w /app/voicemail_intercept.wav "The end of the password is k 3 y !"

    # Generate access log and zip it
    cat << 'EOF' > /app/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "GET /login?user=admin' OR 1=1-- HTTP/1.1" 200 512
172.16.0.2 - - [10/Oct/2023:13:57:11 -0700] "GET /search?q=<script>alert(1)</script> HTTP/1.1" 200 1024
10.0.0.6 - - [10/Oct/2023:13:58:22 -0700] "GET /products?id=1 UNION SELECT null, null-- HTTP/1.1" 200 850
EOF
    cd /app
    zip -P "h4ckk3y!" network_logs.zip access.log
    rm access.log

    # Create reference redactor
    cat << 'EOF' > /app/reference_redactor.py
import sys
import re

def redact(text):
    # Redact CC
    text = re.sub(r'\b(?:\d[ -]*?){13,16}\b', '[REDACTED_CC]', text)
    # Redact SSN
    text = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '[REDACTED_SSN]', text)
    # Neutralize HTML tags
    text = text.replace('<', '&lt;').replace('>', '&gt;')
    return text

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(redact(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
