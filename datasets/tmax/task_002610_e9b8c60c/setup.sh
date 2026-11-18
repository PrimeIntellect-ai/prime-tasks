#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx libc6-dev
    pip3 install pytest

    mkdir -p /home/user/auth_service/logs
    mkdir -p /home/user/auth_service/temp

    cat << 'EOF' > /home/user/auth_service/Makefile
CC=gcc
CFLAGS=-Wall -g
LDFLAGS=

all: auth_server

auth_server: main.o ds.o math_utils.o
	$(CC) $(CFLAGS) -o auth_server main.o math_utils.o $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

ds.o: ds.c
	$(CC) $(CFLAGS) -c ds.c

math_utils.o: math_utils.c
	$(CC) $(CFLAGS) -c math_utils.c

clean:
	rm -f *.o auth_server
EOF

    cat << 'EOF' > /home/user/auth_service/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

extern double compute_token_variance(const char* token);
extern void init_set();
extern int insert_and_check(const char* token);

void process_request(const char* payload, FILE* log_file) {
    char token[16]; // BUB: Too small
    const char* header = strstr(payload, "X-API-Token: ");
    if (header) {
        header += 13;
        const char* end = strchr(header, '\r');
        if (!end) end = strchr(header, '\n');
        if (end) {
            // Memory safety bug here:
            strncpy(token, header, end - header);
            token[end - header] = '\0';

            double var = compute_token_variance(token);
            int replay = insert_and_check(token);
            fprintf(log_file, "Token: %s, Variance: %.2f, Replay: %d\n", token, var, replay);
            fflush(log_file);
        }
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    init_set();
    FILE* log_file = fopen("/home/user/auth_service/auth.log", "a");

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        read(new_socket, buffer, 1024);
        process_request(buffer, log_file);
        char *hello = "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nOK";
        write(new_socket, hello, strlen(hello));
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/auth_service/ds.c
#include <string.h>

#define SET_SIZE 256
char hash_set[SET_SIZE][128];

void init_set() {
    // TODO: implement
}

int insert_and_check(const char* token) {
    // TODO: implement
    return 0;
}
EOF

    cat << 'EOF' > /home/user/auth_service/math_utils.c
#include <math.h>
#include <string.h>

double compute_token_variance(const char* token) {
    // TODO: implement
    return 0.0;
}
EOF

    cat << 'EOF' > /home/user/auth_service/nginx.conf
worker_processes 1;
pid /home/user/auth_service/temp/nginx.pid;
error_log /home/user/auth_service/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/auth_service/temp/client_body;
    proxy_temp_path /home/user/auth_service/temp/proxy;
    fastcgi_temp_path /home/user/auth_service/temp/fastcgi;
    uwsgi_temp_path /home/user/auth_service/temp/uwsgi;
    scgi_temp_path /home/user/auth_service/temp/scgi;

    access_log /home/user/auth_service/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/auth {
            # TODO: Configure proxy_pass
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
