#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make systemd
    pip3 install pytest

    mkdir -p /app/metrics-exporter

    cat << 'EOF' > /app/metrics-exporter/server.cpp
#include <iostream>
#include <string>
#include <thread>
#include <chrono>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

const char* BIND_IP = "127.0.0.2";
const int PORT = 8080;

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr(BIND_IP);
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while (true) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(500));

        std::string response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nmetrics_value 42\n";
        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }

    return 0;
}
EOF

    cat << 'EOF' > /app/metrics-exporter/Makefile
exporter: server.cpp
	g++ -O2 -pthread server.cpp -o exporter
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
