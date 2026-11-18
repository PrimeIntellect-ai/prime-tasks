#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest requests

    mkdir -p /home/user/api_server
    cd /home/user/api_server

    # Create the broken Makefile
    cat << 'EOF' > Makefile
server: main.o rate_limiter.o
	gcc -o server main.o rate_limiter.o

main.o: main.c
	gcc -c main.c

rate_limiter.o: rate_limiter.c
	gcc -c rate_limiter.c

clean:
	rm -f *.o server
EOF

    # Create rate_limiter.h
    cat << 'EOF' > rate_limiter.h
#ifndef RATE_LIMITER_H
#define RATE_LIMITER_H

int check_rate_limit();

#endif
EOF

    # Create rate_limiter.c
    cat << 'EOF' > rate_limiter.c
#include "rate_limiter.h"
#include <math.h>

int request_count = 0;

int check_rate_limit() {
    // Artificial use of math library to require -lm linking
    double dummy = pow(2.0, 3.0);

    if (request_count < 3) {
        request_count++;
        return 1; // Allowed
    }
    return 0; // Rate limited
}
EOF

    # Create main.c
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "rate_limiter.h"

void *handle_connection(void *client_socket_ptr) {
    int client_socket = *(int *)client_socket_ptr;
    free(client_socket_ptr);

    char buffer[1024];
    read(client_socket, buffer, sizeof(buffer) - 1);

    int allowed = check_rate_limit();

    char *response;
    if (allowed) {
        response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!";
    } else {
        response = "HTTP/1.1 429 Too Many Requests\r\nContent-Length: 17\r\n\r\nToo Many Requests";
    }

    write(client_socket, response, strlen(response));
    close(client_socket);
    return NULL;
}

int main() {
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
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

    if (listen(server_fd, 10) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        int *new_socket = malloc(sizeof(int));
        if ((*new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            free(new_socket);
            continue;
        }

        pthread_t thread_id;
        // Artificial use of pthread to require -lpthread linking
        if (pthread_create(&thread_id, NULL, handle_connection, new_socket) != 0) {
            perror("pthread_create");
            close(*new_socket);
            free(new_socket);
        }
        pthread_detach(thread_id);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
