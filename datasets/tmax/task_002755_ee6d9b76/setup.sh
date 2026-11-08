#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/protocol_backend
    cd /home/user/protocol_backend

    cat << 'EOF' > common.h
#ifndef COMMON_H
#define COMMON_H
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// BUG: Multiple definition
int protocol_version = 1;

void log_debug(const char* msg);

#endif
EOF

    cat << 'EOF' > serialize.c
#include "common.h"

void serialize_payload(const char* input, char* output) {
    // Dummy serialization: just copy for this mock
    sprintf(output, "V%d:%s", protocol_version, input);
}
EOF

    cat << 'EOF' > deserialize.c
#include "common.h"

void deserialize_payload(const char* input, char* output) {
    // Dummy deserialization: strip the version header
    const char* colon = strchr(input, ':');
    if (colon) {
        strcpy(output, colon + 1);
    } else {
        strcpy(output, input);
    }
}

void log_debug(const char* msg) {
    printf("DEBUG: %s\n", msg);
}
EOF

    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "common.h"

extern void serialize_payload(const char* input, char* output);
extern void deserialize_payload(const char* input, char* output);

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

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
    address.sin_port = htons(9090);

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
            exit(EXIT_FAILURE);
        }

        memset(buffer, 0, sizeof(buffer));
        read(new_socket, buffer, 1024);

        // basic HTTP parsing
        char* body = strstr(buffer, "\r\n\r\n");
        if (body) {
            body += 4;
            char temp[1024] = {0};
            char res[1024] = {0};

            // For this dummy protocol, we simulate deserializing then re-serializing
            serialize_payload(body, temp);
            deserialize_payload(temp, res);

            char response[2048];
            sprintf(response, "HTTP/1.1 200 OK\r\nContent-Length: %lu\r\n\r\n%s", strlen(res), res);
            write(new_socket, response, strlen(response));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: server

libproto.so: serialize.o deserialize.o
	gcc -shared -o libproto.so serialize.o deserialize.o

serialize.o: serialize.c
	gcc -c -fPIC serialize.c

deserialize.o: deserialize.c
	gcc -c -fPIC deserialize.c

server: server.c libproto.so
	gcc server.c -o server -L. -lproto -Wl,-rpath,.

clean:
	rm -f *.o *.so server
EOF

    cat << 'EOF' > nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        # TODO: proxy configuration
    }
}
EOF

    chown -R user:user /home/user/protocol_backend
    chmod -R 777 /home/user
