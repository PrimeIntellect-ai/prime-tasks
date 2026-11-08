#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetryd
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/telemetryd/server.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include "parser.h"

void* handle_client(void* arg) {
    int sock = *(int*)arg;
    free(arg);

    uint16_t total_len_n;
    if (read(sock, &total_len_n, 2) != 2) {
        close(sock);
        return NULL;
    }

    uint16_t total_len = ntohs(total_len_n);
    if (total_len == 0 || total_len > 8192) {
        close(sock);
        return NULL;
    }

    char *payload = malloc(total_len);
    if (!payload) { close(sock); return NULL; }

    int bytes_read = 0;
    while (bytes_read < total_len) {
        int r = read(sock, payload + bytes_read, total_len - bytes_read);
        if (r <= 0) break;
        bytes_read += r;
    }

    if (bytes_read == total_len) {
        uint16_t offset = 0;
        while (offset < total_len) {
            uint8_t item_len = payload[offset];
            if (item_len == 0) {
                offset++;
                continue;
            }

            // Format parsing edge-case: allocates BEFORE bounds check
            char *item = malloc(item_len);

            if (offset + 1 + item_len > total_len) {
                // Out of bounds - malformed payload
                // BUG: Missing free(item) causing the memory leak
                break;
            }

            memcpy(item, payload + offset + 1, item_len);
            // (Telemetry processing logic would go here)

            free(item);
            offset += 1 + item_len;
        }
    }

    free(payload);
    close(sock);
    return NULL;
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 100) < 0) exit(EXIT_FAILURE);

    while (1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            continue;
        }
        int *client_sock = malloc(sizeof(int));
        *client_sock = new_socket;
        pthread_t thread_id;
        pthread_create(&thread_id, NULL, handle_client, (void*)client_sock);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/telemetryd/parser.h
#ifndef PARSER_H
#define PARSER_H

// BUG: Missing #include <stdint.h>
struct TelemetryHeader {
    uint16_t version;
    uint32_t timestamp;
};

#endif
EOF

    cat << 'EOF' > /home/user/telemetryd/Makefile
CC = gcc
CFLAGS = -Wall -g
# BUG: Missing -pthread

telemetryd: server.c
	$(CC) $(CFLAGS) -o telemetryd server.c

clean:
	rm -f telemetryd
EOF

    cat << 'EOF' > /home/user/telemetryd/test_runner.sh
#!/bin/bash
for f in /home/user/logs/log_*.bin; do
    nc 127.0.0.1 9000 < "$f"
    sleep 0.01
done
EOF
    chmod +x /home/user/telemetryd/test_runner.sh

    cat << 'EOF' > /home/user/logs/generate.py
import struct

for i in range(100):
    filename = f"/home/user/logs/log_{i:03d}.bin"
    with open(filename, "wb") as f:
        if i == 73:
            # Faulty log: Total length is 10, contains a 1-byte length field of 25 (out of bounds)
            # Item length = 25. Mallocs 25. Breaks because 0 + 1 + 25 > 10. Leaks 25 bytes.
            payload = bytes([25, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            f.write(struct.pack("!H", len(payload)))
            f.write(payload)
        else:
            # Valid logs
            payload = bytes([4, 0xA, 0xB, 0xC, 0xD, 3, 0x1, 0x2, 0x3])
            f.write(struct.pack("!H", len(payload)))
            f.write(payload)
EOF
    python3 /home/user/logs/generate.py
    rm /home/user/logs/generate.py

    chmod -R 777 /home/user
