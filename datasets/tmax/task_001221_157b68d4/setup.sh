#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dummy_service.py
import socket
import sys

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8081))
    server.listen(5)
    while True:
        try:
            client, addr = server.accept()
            data = client.recv(1024).decode('utf-8')
            if data == "PING\n":
                client.send("PONG\n".encode('utf-8'))
            client.close()
        except Exception:
            pass

if __name__ == '__main__':
    start_server()
EOF

    chmod -R 777 /home/user
