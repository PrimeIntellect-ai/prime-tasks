#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc libssl-dev openssh-client curl
    pip3 install pytest

    mkdir -p /home/user/app/certs
    mkdir -p /home/user/app/.ssh

    # Generate SSL certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /home/user/app/certs/server.key \
        -out /home/user/app/certs/server.crt \
        -subj "/CN=localhost"

    # Generate SSH keys and set broken permissions
    ssh-keygen -t rsa -b 2048 -f /home/user/app/.ssh/id_rsa -N ""
    chmod 0777 /home/user/app/.ssh/id_rsa
    chmod 0777 /home/user/app/.ssh/id_rsa.pub

    # Create vulnerable backend
    cat << 'EOF' > /home/user/app/backend.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

void encrypt(char *data) {
    for (int i = 0; i < strlen(data); i++) {
        data[i] ^= 0x42;
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};
    char *hello = "HTTP/1.1 200 OK\nSet-Cookie: session=test; Secure; HttpOnly\n\n";

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while (1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        read(new_socket, buffer, 1024);
        encrypt(buffer);
        send(new_socket, hello, strlen(hello), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Create broken nginx config
    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
