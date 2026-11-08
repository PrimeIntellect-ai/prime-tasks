#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    char buffer[1024];
    int bytes_read = read(client_sock, buffer, sizeof(buffer) - 1);
    if (bytes_read <= 0) {
        close(client_sock);
        return;
    }
    buffer[bytes_read] = '\0';

    char method[16], path[256];
    if (sscanf(buffer, "%15s %255s", method, path) != 2) {
        close(client_sock);
        return;
    }

    FILE *log = fopen("/home/user/access.log", "a");
    if (log) {
        fprintf(log, "REQ: %s %s\n", method, path);
        fclose(log);
    }

    if (strncmp(path, "/login?redirect=", 16) == 0) {
        char *target = path + 16;
        char response[512];
        snprintf(response, sizeof(response), "HTTP/1.1 302 Found\r\nLocation: %s\r\n\r\n", target);
        write(client_sock, response, strlen(response));
    } else {
        char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body>Hello</body></html>\n";
        write(client_sock, response, strlen(response));
    }
    close(client_sock);
}

int main() {
    int server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(8080);

    bind(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr));
    listen(server_sock, 5);

    while(1) {
        int client_sock = accept(server_sock, NULL, NULL);
        if (client_sock < 0) continue;
        handle_client(client_sock);
    }
    return 0;
}
EOF

    chown user:user /home/user/server.c
    chmod -R 777 /home/user
