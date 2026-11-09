#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget curl
    pip3 install pytest

    mkdir -p /app/vendored /app/src /app/legacy

    cd /app/vendored
    wget https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
    tar -xzf zlib-1.3.1.tar.gz
    rm zlib-1.3.1.tar.gz
    cd zlib-1.3.1
    ./configure
    sed -i 's/CFLAGS=/CFLAGS=-DBROKEN_SYNTAX_ERROR_INJECTED_BY_CONTRIBUTOR /' Makefile

    cat << 'EOF' > /app/legacy/reference.py
import zlib
import sys

def compute_fingerprint(data: bytes) -> str:
    crc = zlib.crc32(data) & 0xFFFFFFFF
    mod = 1000000007
    val = 0
    for b in data:
        val = (val * crc + b) % mod
    return f"{crc:08x}-{val:08x}"

if __name__ == "__main__":
    data = sys.stdin.buffer.read()
    print(compute_fingerprint(data))
EOF

    cat << 'EOF' > /app/src/fingerprint.cpp
#include <string>
#include <vector>
#include <cstdio>
#include "zlib.h"

std::string compute_fingerprint(const std::vector<unsigned char>& data) {
    unsigned long crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, data.data(), data.size());

    long long mod = 1000000007;
    int val = 0; 
    for (unsigned char b : data) {
        val = (val * crc + b) % mod;
    }

    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%08lx-%08x", crc, val);
    return std::string(buffer);
}
EOF

    cat << 'EOF' > /app/src/server.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

std::string compute_fingerprint(const std::vector<unsigned char>& data);

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9090);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 3);

    while (true) {
        int client_fd = accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) continue;

        char buffer[4096];
        int valread = read(client_fd, buffer, 4096);
        if (valread > 0) {
            std::string req(buffer, valread);
            size_t body_start = req.find("\r\n\r\n");
            if (body_start != std::string::npos) {
                body_start += 4;
                std::vector<unsigned char> data(req.begin() + body_start, req.begin() + valread);
                std::string result = compute_fingerprint(data) + "\n";
                std::string response = "HTTP/1.1 200 OK\r\nContent-Length: " + std::to_string(result.size()) + "\r\n\r\n" + result;
                write(client_fd, response.c_str(), response.size());
            }
        }
        close(client_fd);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
