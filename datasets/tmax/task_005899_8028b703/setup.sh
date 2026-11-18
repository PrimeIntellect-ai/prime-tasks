#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y nginx expect g++ curl

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/nginx/logs /home/user/backend /home/user/backup

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/nginx/logs/access.log;
    server {
        listen 8080;
        location /api {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    # Create backend server.cpp
    cat << 'EOF' > /home/user/backend/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

int main() {
    std::string pin;
    std::cout << "Enter PIN: ";
    std::cin >> pin;
    if (pin != "7788") {
        std::cerr << "Invalid PIN!" << std::endl;
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    // BUG: wrong port
    address.sin_port = htons(8000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        std::cerr << "Bind failed" << std::endl;
        return 1;
    }

    listen(server_fd, 3);
    std::cout << "Listening..." << std::endl;

    while (true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        std::string response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nBackend OK!\n";
        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Set permissions
    chmod -R 777 /home/user
