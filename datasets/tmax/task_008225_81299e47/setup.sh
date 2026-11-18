#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/minilogd_project
    cd /home/user/minilogd_project

    # Create Makefile
    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -g

all: minilogd

minilogd: server.o protocol.o
	$(CC) $(CFLAGS) -o minilogd server.o protocol.o

server.o: server.c protocol.h types.h
	$(CC) $(CFLAGS) -c server.c

protocol.o: protocol.c protocol.h types.h
	$(CC) $(CFLAGS) -c protocol.c

clean:
	rm -f *.o minilogd test_protocol
EOF

    # Create types.h
    cat << 'EOF' > types.h
#ifndef TYPES_H
#define TYPES_H

#include "protocol.h"

typedef struct {
    int id;
    struct ClientMessage msg;
} ClientContext;

#endif
EOF

    # Create protocol.h
    cat << 'EOF' > protocol.h
#ifndef PROTOCOL_H
#define PROTOCOL_H

#include "types.h"

struct ClientMessage {
    int type;
    char* payload;
};

void parse_message(const char* raw, struct ClientMessage* msg);
void process_client_message(const char* raw);

#endif
EOF

    # Create protocol.c
    cat << 'EOF' > protocol.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "protocol.h"

void parse_message(const char* raw, struct ClientMessage* msg) {
    if (strncmp(raw, "MSG:", 4) == 0) {
        msg->type = 1;
        // Bug: Doesn't allocate enough space for null terminator
        msg->payload = malloc(strlen(raw) - 4); 
        strncpy(msg->payload, raw + 4, strlen(raw) - 4);
    } else {
        msg->type = 0;
        msg->payload = NULL;
    }
}
EOF

    # Create server.c
    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "protocol.h"
#include "types.h"

void process_client_message(const char* raw) {
    struct ClientMessage msg;
    parse_message(raw, &msg);
    if (msg.type == 1 && msg.payload != NULL) {
        printf("Received payload: %s\n", msg.payload);
        // Bug: Memory leak, msg.payload is never freed
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <port>\n", argv[0]);
        return 1;
    }
    int port = atoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    printf("Listening on %d...\n", port);

    while(1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);

        char buffer[1024] = {0};
        read(client_fd, buffer, 1024);

        if (strncmp(buffer, "QUIT", 4) == 0) {
            close(client_fd);
            break;
        }

        process_client_message(buffer);
        close(client_fd);
    }
    close(server_fd);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
