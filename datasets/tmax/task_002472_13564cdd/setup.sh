#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /app/provisioner-1.0

    cat << 'EOF' > /app/provisioner-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/stat.h>

void handle_request(int client_socket) {
    char buffer[1024] = {0};
    read(client_socket, buffer, sizeof(buffer) - 1);

    char username[256] = {0};
    char ip[256] = {0};

    if (sscanf(buffer, "GET /provision?username=%255[^&]&ip=%255s", username, ip) == 2) {
        char *base_dir = getenv("BASE_DIR");
        char *www_dir = getenv("WWW_DIR");

        char user_base[512];
        char user_www[512];

        sprintf(user_base, "%s/%s", base_dir, username);
        sprintf(user_www, "%s/%s", www_dir, username);

        mkdir(user_base, 0755);
        mkdir(user_www, 0755);

        char symlink_target[512];
        // BUG: missing / separator
        sprintf(symlink_target, "%s%s", www_dir, username);

        char symlink_path[512];
        sprintf(symlink_path, "%s/www", user_base);

        symlink(symlink_target, symlink_path);

        char route_path[512];
        sprintf(route_path, "%s/route.sh", user_base);

        FILE *f = fopen(route_path, "w");
        if (f) {
            fprintf(f, "ip route add %s via 10.0.0.1", ip);
            fclose(f);
        }

        char *response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
        write(client_socket, response, strlen(response));
    } else {
        char *response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request";
        write(client_socket, response, strlen(response));
    }
    close(client_socket);
}

int main() {
    int server_fd;
    struct sockaddr_in address;

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while (1) {
        int client_socket = accept(server_fd, NULL, NULL);
        handle_request(client_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/provisioner-1.0/Makefile
provisioner: main.c
    gcc -o provisioner main.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
