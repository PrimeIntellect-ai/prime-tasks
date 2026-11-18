#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak nginx curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/backend_instructions.wav "The backend processor must read standard input and output the exact same text, but with all numeric digits from zero to nine removed completely."

    cat << 'EOF' > /opt/oracle_processor.py
#!/usr/bin/env python3
import sys
import re

def process():
    input_text = sys.stdin.read()
    output_text = re.sub(r'[0-9]', '', input_text)
    sys.stdout.write(output_text)

if __name__ == '__main__':
    process()
EOF
    chmod +x /opt/oracle_processor.py

    mkdir -p /home/user
    cat << 'EOF' > /home/user/nginx.conf
error_log /tmp/nginx_error.log;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /tmp/nginx_access.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9999; # Broken: should be 8081
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
