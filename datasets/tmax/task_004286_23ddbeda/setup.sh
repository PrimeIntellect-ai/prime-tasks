#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ netcat-openbsd tar
    pip3 install pytest

    mkdir -p /home/user/network_diag
    cat << 'EOF' > /home/user/network_diag/diag.cpp
#include <iostream>
#include <string>
#include <unistd.h>
#include <ctime>
#include <cstring>
// Missing network headers intentionally:
// #include <sys/socket.h>
// #include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        std::cerr << "Socket creation error" << std::endl;
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9999);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        std::cerr << "Invalid address/ Address not supported" << std::endl;
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cerr << "Connection Failed" << std::endl;
        return -1;
    }

    read(sock, buffer, 1024);

    // Time formatting
    std::time_t t = std::time(nullptr);
    char time_buf[100];
    // Needs to use gmtime and format exactly to YYYY-MM-DD HH:MM:SS
    std::strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", std::gmtime(&t));

    // Remove potential newlines from buffer
    std::string response(buffer);
    if (!response.empty() && response.back() == '\n') {
        response.pop_back();
    }

    std::cout << "[" << time_buf << "] STATUS: " << response << std::endl;
    close(sock);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
