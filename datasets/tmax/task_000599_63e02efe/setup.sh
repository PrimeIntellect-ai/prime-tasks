#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis flask fastapi uvicorn requests

    mkdir -p /app
    cat << 'EOF' > /app/simulator.py
import socket
import time
import threading

def handle_client(conn):
    try:
        while True:
            now = int(time.time() * 1000)
            msg = f"{now},utf-8,dummy data\n".encode('utf-8')
            conn.sendall(msg)
            time.sleep(1)
    except:
        pass
    finally:
        conn.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9000))
    server.listen(5)
    while True:
        conn, addr = server.accept()
        t = threading.Thread(target=handle_client, args=(conn,))
        t.daemon = True
        t.start()

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/simulator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
