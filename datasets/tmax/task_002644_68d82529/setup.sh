#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gdb make git
pip3 install pytest

mkdir -p /app/vendored/ticket_server
cd /app/vendored/ticket_server

git init
git config user.email "dev@example.com"
git config user.name "Dev"

cat << 'EOF' > ticket.h
#ifndef TICKET_H
#define TICKET_H

typedef struct {
    int id;
    double priority;
} Ticket;

#endif
EOF

cat << 'EOF' > config.h
#define ADMIN_TOKEN "8f92a-super-secret-admin-key"
EOF

cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "ticket.h"

#define EXPECTED_TOKEN "8f92a-super-secret-admin-key"

void handle_client(int client_sock) {
    char buffer[1024];
    int read_len = read(client_sock, buffer, sizeof(buffer) - 1);
    if (read_len <= 0) {
        close(client_sock);
        return;
    }
    buffer[read_len] = '\0';

    if (!strstr(buffer, "Auth-Token: " EXPECTED_TOKEN)) {
        char *resp = "HTTP/1.1 401 Unauthorized\r\n\r\n";
        write(client_sock, resp, strlen(resp));
        close(client_sock);
        return;
    }

    Ticket ticket;
    ticket.id = 1;

    const char *data = "PRIORITY 4.50291";
    sscanf(data, "%*s %lf", &ticket.priority);

    char resp[1024];
    sprintf(resp, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
                  "{\"status\": \"ok\", \"tickets\": [{\"id\": %d, \"priority\": %g}]}", 
            ticket.id, ticket.priority);

    write(client_sock, resp, strlen(resp));
    close(client_sock);
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    int port = atoi(argv[1]);

    int server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    bind(server_sock, (struct sockaddr *)&addr, sizeof(addr));
    listen(server_sock, 5);

    while (1) {
        int client_sock = accept(server_sock, NULL, NULL);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
EOF

cat << 'EOF' > Makefile
ticket_server: server.c
	gcc -g -O0 server.c -o ticket_server
EOF

git add ticket.h config.h server.c Makefile
git commit -m "Initial commit with config"

rm config.h
git add -u
git commit -m "Security: remove config.h"

sed -i 's/double priority;/float priority;/g' ticket.h
git add ticket.h
git commit -m "Optimization: use float for priority to save memory"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app/vendored/ticket_server
