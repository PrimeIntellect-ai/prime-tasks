#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3 curl
    pip3 install pytest flask requests

    mkdir -p /home/user/app/engine
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/data

    # Create C++ Engine
    cat << 'EOF' > /home/user/app/engine/engine.cpp
#include <iostream>
#include <string>
#include <cmath>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

using namespace std;

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8001);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        double x = 0.0;
        try {
            x = std::stod(buffer);
        } catch(...) {}

        float sum = 0.0;
        float term = x;
        int n = 1;

        // Buggy loop condition and precision
        while (term > 1e-7) {
            sum += term;
            term = -term * x * x / ((2 * n) * (2 * n + 1));
            n++;
        }

        std::string res = std::to_string(sum);
        send(new_socket, res.c_str(), res.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Create Flask API Gateway
    cat << 'EOF' > /home/user/app/gateway/app.py
from flask import Flask, request
import sqlite3
import socket

app = Flask(__name__)

@app.route('/price')
def price():
    id_val = request.args.get('id', '0')
    try:
        conn = sqlite3.connect('/home/user/app/data/recovered_cache.db')
        c = conn.cursor()
        c.execute("SELECT price FROM cache WHERE id=?", (id_val,))
        row = c.fetchone()
        conn.close()
        if row:
            return str(row[0])
    except Exception as e:
        pass

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8001))
        s.sendall(id_val.encode())
        data = s.recv(1024)
        s.close()
        return data.decode()
    except:
        return "Error", 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    # Create and corrupt SQLite database
    sqlite3 /home/user/app/data/cache.db "CREATE TABLE cache (id TEXT, price REAL); INSERT INTO cache VALUES ('test', 99.99);"
    dd if=/dev/urandom of=/home/user/app/data/cache.db bs=1 count=100 seek=16 conv=notrunc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
