#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libssl-dev ffmpeg espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/intercepted_comms.wav "The secret passphrase is sunflower."

    mkdir -p /home/user/server_src

    cat << 'EOF' > /home/user/server_src/auth.h
#ifndef AUTH_H
#define AUTH_H
#define SECRET_PASSPHRASE "CHANGEME"
#endif
EOF

    cat << 'EOF' > /home/user/server_src/crypto.h
#ifndef CRYPTO_H
#define CRYPTO_H
int base64_decode(const char *in, unsigned char *out, int out_len);
#endif
EOF

    cat << 'EOF' > /home/user/server_src/crypto.c
#include <string.h>
#include <openssl/evp.h>
#include "crypto.h"
int base64_decode(const char *in, unsigned char *out, int out_len) {
    return EVP_DecodeBlock(out, (const unsigned char *)in, strlen(in));
}
EOF

    cat << 'EOF' > /home/user/server_src/http.h
#ifndef HTTP_H
#define HTTP_H
void handle_client(int client_fd);
#endif
EOF

    cat << 'EOF' > /home/user/server_src/http.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <openssl/evp.h>
#include "http.h"
#include "auth.h"
#include "crypto.h"

void handle_client(int client_fd) {
    char buffer[2048] = {0};
    read(client_fd, buffer, sizeof(buffer)-1);

    char expected_plain[256];
    snprintf(expected_plain, sizeof(expected_plain), "admin:%s", SECRET_PASSPHRASE);

    char expected_b64[512] = {0};
    EVP_EncodeBlock((unsigned char *)expected_b64, (const unsigned char *)expected_plain, strlen(expected_plain));

    char auth_header[512];
    snprintf(auth_header, sizeof(auth_header), "Authorization: Basic %s", expected_b64);

    if (strstr(buffer, auth_header) != NULL) {
        char response[] = "HTTP/1.1 200 OK\r\n\r\nAccess Granted\n";
        write(client_fd, response, strlen(response));
    } else {
        char response[] = "HTTP/1.1 401 Unauthorized\r\n\r\nDenied\n";
        write(client_fd, response, strlen(response));
    }
    close(client_fd);
}
EOF

    cat << 'EOF' > /home/user/server_src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "http.h"

int main(int argc, char *argv[]) {
    int port = 8080;
    if (argc > 1) port = atoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        int client_fd = accept(server_fd, NULL, NULL);
        handle_client(client_fd);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/server_src/test.c
#include <stdio.h>
int main() {
    printf("Tests passed.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/server_src/bench.c
#include <stdio.h>
int main() {
    printf("Benchmark complete.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/server_src/Makefile
CC=gcc
CFLAGS=-Wall -Wextra -O2

all: http_server test_suite bench_suite

http_server: main.o http.o crypto.o
	$(CC) $(CFLAGS) -lcrypto -lpthread -o http_server main.o http.o crypto.o

test_suite: test.o crypto.o
	$(CC) $(CFLAGS) -o test_suite test.o crypto.o -lcrypto

bench_suite: bench.o crypto.o
	$(CC) $(CFLAGS) -o bench_suite bench.o crypto.o -lcrypto

test: test_suite
	./test_suite

bench: bench_suite
	./bench_suite
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
