#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        qemu-utils \
        socat \
        procps \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,50 'Gateway Port: 8111'" \
        -draw "text 20,100 'Internal Storage Port: 9222'" \
        /app/diagram.png

    dd if=/dev/zero of=/tmp/raw_source.img bs=1M count=50
    dd if=/dev/urandom of=/tmp/raw_source.img bs=1M count=2 conv=notrunc seek=10

    cat << 'EOF' > /tmp/serve_disk.py
import socket
import sys

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 9222))
    s.listen(1)
    while True:
        try:
            conn, addr = s.accept()
            with open('/tmp/raw_source.img', 'rb') as f:
                conn.sendall(f.read())
            conn.close()
        except Exception:
            pass

if __name__ == '__main__':
    serve()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
