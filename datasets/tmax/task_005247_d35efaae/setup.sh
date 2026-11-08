#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        gdb \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        curl

    pip3 install pytest

    mkdir -p /home/user/telemetryd
    mkdir -p /app

    # Generate the server_notes.png image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +20+40 "Deploy Telemetry Server ASAP" \
        -annotate +20+80 "PORT: 8088" \
        -annotate +20+120 "AUTH_TOKEN: f9a3b2c1-telemetry-token" \
        /app/server_notes.png

    # Create Makefile with missing -lpthread flag
    cat << 'EOF' > /home/user/telemetryd/Makefile
CC=gcc
CFLAGS=-Wall -g

telemetryd: server.o
	$(CC) $(CFLAGS) -o telemetryd server.o

server.o: server.c
	$(CC) $(CFLAGS) -c server.c

clean:
	rm -f *.o telemetryd
EOF

    # Create server.c with deliberate null pointer dereference
    cat << 'EOF' > /home/user/telemetryd/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>

void* handle_request(void* arg) {
    int client_sock = *(int*)arg;
    free(arg);

    char buffer[1024];
    int bytes_read = read(client_sock, buffer, sizeof(buffer)-1);
    if (bytes_read > 0) {
        buffer[bytes_read] = '\0';
    }

    // Deliberate null pointer dereference to cause segfault
    char *bad_ptr = NULL;
    *bad_ptr = 'X';

    const char *response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\": \"healthy\"}\n";
    write(client_sock, response, strlen(response));
    close(client_sock);
    return NULL;
}

int main() {
    FILE *f = fopen("config.ini", "r");
    if (!f) {
        printf("Missing config.ini\n");
        return 1;
    }
    int port = 0;
    char token[256] = {0};

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        sscanf(line, "PORT=%d", &port);
        sscanf(line, "AUTH_TOKEN=%255s", token);
    }
    fclose(f);

    if (port == 0) {
        printf("Invalid port\n");
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }
    listen(server_fd, 5);
    printf("Server listening on port %d...\n", port);

    while(1) {
        int client_sock = accept(server_fd, NULL, NULL);
        if (client_sock < 0) continue;

        pthread_t thread_id;
        int *arg = malloc(sizeof(int));
        *arg = client_sock;
        pthread_create(&thread_id, NULL, handle_request, arg);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
