#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_email_daemon.py
import socket
import sys

def run_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8025))
    server.listen(5)

    while True:
        client, _ = server.accept()
        # Silent rejection without token
        token = client.recv(1024).decode('utf-8', errors='ignore')
        if not token.startswith("AUTH_TOKEN: obs_admin\n"):
            client.close()
            continue

        client.sendall(b"220 Mock SMTP Service Ready\r\n")
        while True:
            data = client.recv(1024)
            if not data:
                break
            cmd = data.decode('utf-8', errors='ignore').strip()
            if cmd.startswith("EHLO"):
                client.sendall(b"250 Hello\r\n")
            elif cmd == "QUIT":
                client.sendall(b"221 Bye\r\n")
                break
            elif cmd == "CRASH":
                sys.exit(1)
            else:
                client.sendall(b"500 Unknown command\r\n")
        client.close()

if __name__ == '__main__':
    run_server()
EOF

    chmod -R 777 /home/user
