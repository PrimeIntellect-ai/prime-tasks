#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/.config/systemd/user/backend.service
[Unit]
Description=Backend Status Service

[Service]
ExecStart=/usr/bin/python3 -c "import http.server, socketserver; Handler = http.server.SimpleHTTPRequestHandler; socketserver.TCPServer(('127.0.0.1', 9091), Handler).serve_forever()"
Restart=always

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/proxy.service
[Unit]
Description=C Reverse Proxy

[Service]
ExecStart=/home/user/health_proxy
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /home/user/health_proxy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define LOG_FILE "/home/user/proxy_access.log"

void log_request() {
    FILE *f = fopen(LOG_FILE, "a");
    if (f) {
        fprintf(f, "Request forwarded to backend\n");
        fclose(f);
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(9090);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }

        read(new_socket, buffer, 1024);
        log_request();

        char *response = "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nBackend reached via Proxy\n";
        send(new_socket, response, strlen(response), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    chown -R user:user /home/user/logs /home/user/.config /home/user/health_proxy.c
    chmod -R 777 /home/user
