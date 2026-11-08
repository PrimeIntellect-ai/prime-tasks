#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx socat curl
    pip3 install pytest

    mkdir -p /home/user/service /home/user/nginx /home/user/data
    mkdir -p /home/user/nginx/logs /home/user/nginx/temp

    # Create target file
    echo -n "CLOUD_REGION_EU_WEST_1" > /home/user/data/migration_target.txt

    # Create broken C++ file
    cat << 'EOF' > /home/user/service/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

int main() {
    int server_fd, new_socket;
    struct sockaddr_un address;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    // BUG: Wrong socket path
    strcpy(address.sun_path, "/home/user/service/wrong.sock");
    unlink(address.sun_path);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(true) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }

        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        std::string req(buffer);

        if (req.find("GET /api/migrate") != std::string::npos) {
            std::ifstream t_file("/home/user/data/migration_target.txt");
            std::string target((std::istreambuf_iterator<char>(t_file)), std::istreambuf_iterator<char>());

            std::ofstream s_file("/home/user/data/migration_status.txt");
            s_file << "MIGRATION_COMPLETE_TO_" << target;
            s_file.close();

            std::string response = "HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nSuccess";
            write(new_socket, response.c_str(), response.length());
        } else {
            std::string response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
            write(new_socket, response.c_str(), response.length());
        }
        close(new_socket);
    }
    return 0;
}
EOF

    # Create base Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;
    access_log /home/user/nginx/logs/access.log;

    server {
        # Needs to be set to 8080 and configured for proxy_pass to UDS
        listen 8081; # INTENTIONAL BUG

        location /api/ {
            # Needs to be configured correctly
            proxy_pass http://unix:/home/user/service/wrong.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
