#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx git g++ curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Nginx setup
    mkdir -p /home/user/nginx/logs
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/logs/access.log;
    server {
        listen 8000;
        location / {
            proxy_pass http://127.0.0.1:8081; # BUG: should be 8080
        }
    }
}
EOF

    # Git repo and C++ app setup
    mkdir -p /home/user/repo.git
    cd /home/user/repo.git
    git init --bare

    mkdir -p /home/user/workspace
    cd /home/user/workspace
    git clone /home/user/repo.git .

    cat << 'EOF' > server.cpp
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

int main() {
    // Intentional crash if logs directory doesn't exist
    std::ofstream logfile("logs/startup.log", std::ios::app);
    if (!logfile.is_open()) {
        std::cerr << "Failed to open log file. Exiting." << std::endl;
        return 1;
    }

    // System call relying on PATH and TZ
    int res = std::system("date > logs/startup.log");
    if (res != 0) {
        std::cerr << "Date command failed." << std::endl;
        return 1;
    }

    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while (true) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        std::string response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nBackend running!\n";
        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    git add server.cpp
    git config user.email "admin@example.com"
    git config user.name "Admin"
    git commit -m "Initial commit"
    git push origin master

    chmod -R 777 /home/user
