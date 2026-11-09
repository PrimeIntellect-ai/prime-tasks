#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/src

    # Generate intercepted audio file
    espeak -w /app/intercepted_call.wav "Hey, it's Dave. I left the backdoor in the auth module. Just set the dev_override cookie to OmegaProtocol99. Make sure nobody finds out."

    # Create and compile auth.o
    cat << 'EOF' > /tmp/auth.c
#include <string.h>

int check_auth(const char* cookie_header) {
    if (cookie_header && strstr(cookie_header, "dev_override=OmegaProtocol99")) {
        return 1;
    }
    return 0;
}
EOF
    gcc -c /tmp/auth.c -o /home/user/auth.o
    rm /tmp/auth.c

    # Create vulnerable server.c
    cat << 'EOF' > /home/user/src/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

extern int check_auth(const char* cookie_header);

void log_headers(const char* headers) {
    FILE *f = fopen("/home/user/server.log", "a");
    if (f) {
        fprintf(f, "%s\n", headers);
        fclose(f);
    }
}

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

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

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
            continue;
        }

        read(new_socket, buffer, 4096);
        log_headers(buffer);

        char *next = strstr(buffer, "GET /login?next=");
        if (next) {
            next += 16;
            char *end = strchr(next, ' ');
            if (end) {
                *end = '\0';
                char response[1024];
                sprintf(response, "HTTP/1.1 302 Found\r\nLocation: %s\r\n\r\n", next);
                write(new_socket, response, strlen(response));
            }
        } else {
            char *cookie = strstr(buffer, "Cookie:");
            if (cookie && check_auth(cookie)) {
                char *response = "HTTP/1.1 200 OK\r\n\r\nAuthenticated";
                write(new_socket, response, strlen(response));
            } else {
                char *response = "HTTP/1.1 401 Unauthorized\r\n\r\n";
                write(new_socket, response, strlen(response));
            }
        }

        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
