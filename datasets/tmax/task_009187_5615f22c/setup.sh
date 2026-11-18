#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_server.py
import socket
import sys

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9090))
    server.listen(5)

    try:
        while True:
            client, _ = server.accept()
            data = client.recv(1024)
            if data:
                client.sendall(b"SENSOR_ACK: " + data)
            client.close()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()

if __name__ == '__main__':
    main()
EOF
    chmod +x /home/user/sensor_server.py

    chmod -R 777 /home/user
