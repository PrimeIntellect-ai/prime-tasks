#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl
    pip3 install pytest

    mkdir -p /home/user/api_server
    cd /home/user/api_server

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -Werror -O3
LDFLAGS = 

all: server

server: main.o api.o hash.o
	$(CC) $(CFLAGS) -o server main.o api.o hash.o $(LDFLAGS)

clean:
	rm -f *.o server
EOF
    echo '%.o: %.c' >> Makefile
    echo '	$(CC) $(CFLAGS) -c $< -o $@' >> Makefile

    cat << 'EOF' > hash.c
#include <stdint.h>

uint32_t fast_hash(const char *str) {
    uint32_t hash = 5381;
    int c;
    while ((c = *str++)) {
        // Bug: missing %eax in clobber list
        __asm__ (
            "mov %1, %%eax\n\t"
            "shl $5, %%eax\n\t"
            "add %1, %%eax\n\t"
            "add %2, %%eax\n\t"
            "mov %%eax, %0"
            : "=r" (hash)
            : "0" (hash), "r" (c)
            // MISSING CLOBBER: : "%eax"
        );
    }
    return hash;
}
EOF

    cat << 'EOF' > api.h
#ifndef API_H
#define API_H

typedef struct {
    char *ip_addr;
    char *auth_token;
} RequestContext;

int process_request(const char *ip, const char *auth_header);

#endif
EOF

    cat << 'EOF' > api.c
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "api.h"

extern uint32_t fast_hash(const char *str);

#define MAX_IPS 100
uint32_t rate_limits[MAX_IPS] = {0};
int rate_limit_counts[MAX_IPS] = {0};

int process_request(const char *ip, const char *auth_header) {
    RequestContext *ctx = malloc(sizeof(RequestContext));
    ctx->ip_addr = strdup(ip);

    if (auth_header == NULL || strncmp(auth_header, "Bearer ", 7) != 0) {
        // Bug: Memory leak, missing free(ctx->ip_addr) and free(ctx)
        return 400; 
    }
    ctx->auth_token = strdup(auth_header + 7);

    uint32_t h = fast_hash(ctx->ip_addr);
    int found = -1;
    for (int i=0; i<MAX_IPS; i++) {
        if (rate_limits[i] == h) { found = i; break; }
        if (rate_limits[i] == 0) { found = i; rate_limits[i] = h; break; }
    }

    int status = 200;
    if (found != -1) {
        if (rate_limit_counts[found] >= 2) {
            status = 429;
        } else {
            rate_limit_counts[found]++;
        }
    }

    free(ctx->ip_addr);
    free(ctx->auth_token);
    free(ctx);
    return status;
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "api.h"

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);

        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        char *auth_ptr = strstr(buffer, "Authorization: ");
        char auth_header[256] = {0};
        if (auth_ptr) {
            sscanf(auth_ptr, "Authorization: %[^\r\n]", auth_header);
        }

        int status = process_request("127.0.0.1", auth_header[0] ? auth_header : NULL);

        char response[256];
        sprintf(response, "HTTP/1.1 %d OK\r\nContent-Length: 0\r\n\r\n", status);
        write(new_socket, response, strlen(response));
        close(new_socket);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/api_server
    chmod -R 777 /home/user
