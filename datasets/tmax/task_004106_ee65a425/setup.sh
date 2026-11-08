#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc redis-server strace ltrace binutils
pip3 install pytest flask redis

mkdir -p /app/.oracle

cat << 'EOF' > /app/auth_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

void generate_token(const char* input, char* output) {
    int len = strlen(input);
    for(int i=0; i<len; i++) {
        unsigned char c = (input[i] ^ 0x42) + 0x07;
        sprintf(output + (i*2), "%02x", c);
    }
}

int main() {
    int server_fd, client_fd;
    struct sockaddr_un server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);
    char buffer[256];
    char token[512];

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(1);
    }

    server_addr.sun_family = AF_UNIX;
    strcpy(server_addr.sun_path, "/tmp/auth.sock");
    unlink("/tmp/auth.sock");

    if (bind(server_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind");
        exit(1);
    }

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(1);
    }

    while (1) {
        client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            perror("accept");
            continue;
        }

        int n = read(client_fd, buffer, sizeof(buffer) - 1);
        if (n > 0) {
            buffer[n] = '\0';
            buffer[strcspn(buffer, "\r\n")] = 0;
            generate_token(buffer, token);
            write(client_fd, token, strlen(token));
        }
        close(client_fd);
    }
    close(server_fd);
    return 0;
}
EOF

gcc /app/auth_daemon.c -o /app/auth_daemon
rm /app/auth_daemon.c

cat << 'EOF' > /app/api_gateway.py
from flask import Flask, request, jsonify
import redis
import json
import socket

app = Flask(__name__)

with open('/app/config.json') as f:
    config = json.load(f)

r = redis.Redis(host=config.get('REDIS_HOST', 'localhost'), port=config.get('REDIS_PORT', 6379), db=0)

@app.route('/auth', methods=['POST'])
def auth():
    data = request.json
    username = data.get('username')

    try:
        r.ping()
    except Exception as e:
        return jsonify({"error": "Redis connection failed"}), 500

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(config.get('AUTH_SOCKET', '/tmp/auth.sock'))
        sock.sendall(username.encode())
        token = sock.recv(512).decode()
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        sock.close()

    return jsonify({"token": token})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

cat << 'EOF' > /app/config.json
{
  "REDIS_HOST": "unknown",
  "REDIS_PORT": 0,
  "AUTH_SOCKET": "/var/run/missing.sock"
}
EOF

cat << 'EOF' > /app/.oracle/oracle_token.py
import sys

def gen(username):
    return ''.join(f'{((ord(c) ^ 0x42) + 0x07) & 0xFF:02x}' for c in username)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(gen(sys.argv[1]))
EOF

chmod -R 755 /app
chmod 666 /app/config.json

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
