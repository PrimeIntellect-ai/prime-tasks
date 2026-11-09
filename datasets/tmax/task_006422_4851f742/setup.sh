#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_services.py
import socket
import threading
import time

def handle_client(conn, expected_response):
    try:
        data = conn.recv(1024).decode('utf-8')
        if data == "STATUS_REQ\n":
            conn.sendall(expected_response.encode('utf-8'))
    except Exception:
        pass
    finally:
        conn.close()

def start_server(port, expected_response):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn, expected_response), daemon=True).start()

threading.Thread(target=start_server, args=(9001, "OK\n"), daemon=True).start()
threading.Thread(target=start_server, args=(9002, "ERROR\n"), daemon=True).start()

while True:
    time.sleep(1)
EOF

    chmod -R 777 /home/user
