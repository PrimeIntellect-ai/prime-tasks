#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc
    pip3 install pytest flask requests

    mkdir -p /app

    cat << 'EOF' > /app/nginx.conf
events {
    worker_connections 1024;
}
http {
    # Add server block here to proxy 8080 to 127.0.0.1:5000
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request
import socket

app = Flask(__name__)

@app.route('/')
def index():
    return "OK", 200

@app.route('/check_access', methods=['POST'])
def check_access():
    username = request.form.get('username', '')
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 9000))
        s.sendall(username.encode('utf-8'))
        response = s.recv(1024)
        s.close()
        return response.decode('utf-8'), 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /tmp/auth-daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    int is_admin = 0;
    char buffer[32];

    // Vulnerability: buffer overflow
    read(client_sock, buffer, 128);

    if (is_admin != 0) {
        write(client_sock, "ADMIN_GRANTED", 13);
    } else {
        write(client_sock, "ACCESS_DENIED", 13);
    }
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    server_addr.sin_port = htons(9000);

    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        exit(1);
    }
    listen(server_sock, 5);

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
EOF

    gcc -fno-stack-protector -z execstack -o /app/auth-daemon /tmp/auth-daemon.c
    rm /tmp/auth-daemon.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
