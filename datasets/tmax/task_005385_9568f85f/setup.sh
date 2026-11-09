#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[4096] = {0};

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
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 10) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }
        memset(buffer, 0, 4096);
        read(new_socket, buffer, 4095);

        char *redirect = strstr(buffer, "redirect=");
        char redir_url[256] = "/";
        if (redirect) {
            sscanf(redirect, "redirect=%255[^ \t\r\n&]", redir_url);
        }

        if (strstr(buffer, "username=admin") && strstr(buffer, "password=v1nt4g3_p4ssw0rd")) {
            char response[1024];
            snprintf(response, sizeof(response), "HTTP/1.1 302 Found\r\nLocation: %s\r\nSet-Cookie: session_id=deadbeef12345678\r\nContent-Length: 0\r\n\r\n", redir_url);
            write(new_socket, response, strlen(response));
        } else {
            char *response = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n";
            write(new_socket, response, strlen(response));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    gcc /tmp/server.c -o /app/legacy_auth
    strip /app/legacy_auth
    rm /tmp/server.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
