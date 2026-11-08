#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make patch netcat
    pip3 install pytest

    mkdir -p /home/user/math_service

    cat << 'EOF' > /home/user/math_service/mathcore.h
#ifndef MATHCORE_H
#define MATHCORE_H

void compute_factors(int n, char* output);

#ifdef ENABLE_ADV_MATH
void compute_factors_adv(int n, char* output);
#endif

#endif
EOF

    cat << 'EOF' > /home/user/math_service/mathcore.c
#include <stdio.h>
#include "mathcore.h"

void compute_factors(int n, char* output) {
    sprintf(output, "BASIC:%d", n);
}
EOF

    cat << 'EOF' > /home/user/math_service/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "mathcore.h"

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};
    char output[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);
        read(new_socket, buffer, 1024);
        int n = atoi(buffer);

        // Validation missing here

#ifdef ENABLE_ADV_MATH
        compute_factors_adv(n, output);
#else
        compute_factors(n, output);
#endif

        strcat(output, "\n");
        send(new_socket, output, strlen(output), 0);
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
        memset(output, 0, sizeof(output));
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_service/Makefile
CC=gcc
CFLAGS=-Wall

all: math_server

libmathcore.so: mathcore.c
	$(CC) $(CFLAGS) -shared -o libmathcore.so mathcore.c

math_server: server.c libmathcore.so
	$(CC) $(CFLAGS) -o math_server server.c -lmathcore

clean:
	rm -f *.so math_server
EOF

    cat << 'EOF' > /home/user/math_service/feature.patch
--- mathcore.c
+++ mathcore.c
@@ -5,3 +5,9 @@
 void compute_factors(int n, char* output) {
     sprintf(output, "BASIC:%d", n);
 }
+
+#ifdef ENABLE_ADV_MATH
+void compute_factors_adv(int n, char* output) {
+    sprintf(output, "ADVANCED:%d", n * 2);
+}
+#endif
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
