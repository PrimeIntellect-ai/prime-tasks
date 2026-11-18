#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io docker-compose
    pip3 install pytest

    mkdir -p /app/static
    mkdir -p /home/user/www

    cat << 'EOF' > /app/static/index.html
<html><body>Success</body></html>
EOF

    cat << 'EOF' > /app/docker-compose.yml
version: '3'
services:
  proxy:
    image: nginx:latest
    volumes:
      - /home/user/www:/usr/share/nginx/html
  backend:
    image: python:3.9-slim
    command: python -m http.server 5000
EOF

    cat << 'EOF' > /app/oracle_process_log.py
import sys
import re

def main():
    if len(sys.argv) < 2:
        return
    log_line = sys.argv[1]
    match = re.match(r'^(\S+)\s+\S+\s+\S+\s+\[.*?\]\s+"(\S+)\s+(\S+)\s+.*?"\s+(\d+)\s+', log_line)
    if match:
        ip, method, path, status = match.groups()
        output = f"IP: {ip} | METHOD: {method} | PATH: {path} | STATUS: {status}"
        if int(status) >= 400:
            output += " | ERROR"
        print(output)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/www
    chmod -R 777 /home/user
