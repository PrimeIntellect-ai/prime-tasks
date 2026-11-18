#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        libssl-dev \
        openssl \
        fonts-dejavu-core \
        g++

    pip3 install pytest

    mkdir -p /app

    # Generate self-signed cert
    openssl req -x509 -newkey rsa:4096 -keyout /app/server.key -out /app/server.crt -days 365 -nodes -subj "/CN=localhost"

    # Generate target config image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,50 'TARGET_IP: 127.0.0.1'" \
        -draw "text 10,100 'SCAN_RANGE: 8440-8450'" \
        /app/target_config.png

    # Create mock server script
    cat << 'EOF' > /app/start_mock_server.sh
#!/usr/bin/env python3
import socket
import ssl
import random
import sys

port = random.randint(8440, 8450)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/app/server.crt', '/app/server.key')

with socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', port))
    sock.listen(1)
    print(f"Mock server listening on 127.0.0.1:{port}...")

    while True:
        try:
            conn, addr = sock.accept()
            with context.wrap_socket(conn, server_side=True) as ssock:
                ssock.sendall(b"FLAG{tls_evasion_successful_992}")
        except Exception as e:
            print(f"Connection error: {e}")
EOF
    chmod +x /app/start_mock_server.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
