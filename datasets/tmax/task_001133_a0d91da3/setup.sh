#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx g++ curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/conf
    mkdir -p /home/user/app/src

    cat << 'EOF' > /home/user/app/conf/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/app/logs/error.log;
pid /home/user/app/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/app/logs/access.log;

    upstream cpp_backend {
        # Intentional 502 bad gateway trigger
        server 127.0.0.1:9999;
    }

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://cpp_backend;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/src/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        std::string request(buffer);
        std::string response;

        if (request.find("GET /health") != std::string::npos) {
            // AGENT MUST IMPLEMENT THIS
            // response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
            response = "HTTP/1.1 500 Internal Server Error\r\n\r\nFAIL";
        } else {
            response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World!";
        }

        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
