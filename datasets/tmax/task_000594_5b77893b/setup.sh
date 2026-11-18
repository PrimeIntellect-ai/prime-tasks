#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl socat logrotate curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        std::cout << "Connection received" << std::endl;
        std::string response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
