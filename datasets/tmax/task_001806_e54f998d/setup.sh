#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        tesseract-ocr \
        libjansson-dev \
        imagemagick \
        fonts-dejavu

    pip3 install pytest requests

    mkdir -p /app
    mkdir -p /opt/legacy/lib

    # Create a dummy conflicting library
    echo "invalid elf" > /opt/legacy/lib/libjansson.so

    # Generate the device label image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'DEVICE_SN: 2147483' text 20,100 'MAGIC_KEY: 1500'" /app/device_label.png

    # Create the buggy C server
    cat << 'EOF' > /app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <jansson.h>

void process_telemetry(int sn, int key, char* output) {
    int hash = sn * key; // OVERFLOWS!
    sprintf(output, "%ld", (long)hash);
}

void *handle_client(void *arg) {
    int client_socket = *(int*)arg;
    free(arg);
    char buffer[1024] = {0};
    read(client_socket, buffer, 1024);

    int sn = 0, key = 0;
    char *sn_str = strstr(buffer, "sn=");
    char *key_str = strstr(buffer, "key=");
    if (sn_str) sn = atoi(sn_str + 3);
    if (key_str) key = atoi(key_str + 4);

    char output[256];
    process_telemetry(sn, key, output);

    char response[1024];
    sprintf(response, "HTTP/1.1 200 OK\r\nContent-Length: %lu\r\n\r\n%s", strlen(output), output);
    write(client_socket, response, strlen(response));
    close(client_socket);
    return NULL;
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    // Dummy jansson call to ensure linkage
    json_t *dummy = json_object();
    json_decref(dummy);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        pthread_t thread_id;
        int *client_sock = malloc(sizeof(int));
        *client_sock = new_socket;
        pthread_create(&thread_id, NULL, handle_client, (void*)client_sock);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    # Set up user
    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
