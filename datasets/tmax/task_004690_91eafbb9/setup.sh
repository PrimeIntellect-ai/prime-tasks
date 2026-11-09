#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/server.py
import socket
import time

data = [
    "1,100,50.0,1024\n",
    "2,101,60.0,1024\n",
    "1,100,50.0,1024\n", # duplicate
    "3,102,70.0,2048\n",
    "4,103,20.0,2048\n",
    "3,102,70.0,2048\n", # duplicate
    "4,103,20.0,2048\n", # duplicate
    "5,104,30.0,1024\n",
    "6,105,40.0,4096\n",
    "7,106,80.0,4096\n",
    "6,105,40.0,4096\n", # duplicate
    "8,107,15.0,2048\n"
]

def start_server():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(('127.0.0.1', 8080))
    server_socket.listen(1)

    while True:
        conn, addr = server_socket.accept()
        for line in data:
            conn.sendall(line.encode('utf-8'))
            time.sleep(0.01) # Simulate slight network delay
        conn.close()

if __name__ == '__main__':
    start_server()
EOF

chmod -R 777 /home/user
