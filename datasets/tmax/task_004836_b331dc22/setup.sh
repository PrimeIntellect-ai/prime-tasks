#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_daemon.c
#include <stdio.h>

const char key[] = "KEY_ID=B4ckD00rK3y_2023";
const char iv[] = "IV_ID=IV_v3ctor_123456";

int main() {
    printf("Auth Daemon Running...\n");
    return 0;
}
EOF

    gcc /home/user/auth_daemon.c -o /home/user/auth_daemon

    cat << 'EOF' > /home/user/simulation.py
import socket
import threading
import time
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

TARGET_PORT = 10037
KEY = b"B4ckD00rK3y_2023"
IV = b"IV_v3ctor_123456"

PAYLOAD = b'{"salt": "s4lty_str", "hashes": {"user1": "5605d1fb1b693ce1db0799778cdce6cb4e5b7c7eb3cc38dcda50c60da30d8d09", "user2": "c4d516e8851e50f584e031649969185a1a1f09bb097e37ff34b7f0e75a5c64dc"}}'

padder = padding.PKCS7(128).padder()
padded_data = padder.update(PAYLOAD) + padder.finalize()
cipher = Cipher(algorithms.AES(KEY), modes.CBC(IV), backend=default_backend())
encryptor = cipher.encryptor()
encrypted_payload = encryptor.update(padded_data) + encryptor.finalize()

def handle_client(client_socket, port):
    try:
        if port == TARGET_PORT:
            client_socket.sendall(encrypted_payload)
    except:
        pass
    finally:
        client_socket.close()

def start_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(('127.0.0.1', port))
        server.listen(5)
        while True:
            client, _ = server.accept()
            threading.Thread(target=handle_client, args=(client, port)).start()
    except Exception:
        pass

for p in range(10000, 10051):
    threading.Thread(target=start_server, args=(p,), daemon=True).start()

while True:
    time.sleep(1)
EOF

    chmod -R 777 /home/user
