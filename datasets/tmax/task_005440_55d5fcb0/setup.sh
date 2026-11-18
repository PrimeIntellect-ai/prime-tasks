#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc haproxy netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/mail_worker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>

void *handle_client(void *arg) {
    int client_socket = *(int *)arg;
    free(arg);
    char buffer[1024];
    int n = read(client_socket, buffer, sizeof(buffer));
    if (n > 0) {
        char *response = "250 OK \n";
        write(client_socket, response, strlen(response));
    }
    close(client_socket);
    return NULL;
}

int main(int argc, char *argv[]) {
    if (getenv("CLUSTER_NAME") == NULL) {
        return 1;
    }
    char *port = NULL;
    for (int i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--port") == 0) && i + 1 < argc) {
            port = argv[i + 1];
            break;
        }
    }
    if (port == NULL) {
        return 1;
    }
    int server_socket = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(atoi(port));

    if (bind(server_socket, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        return 1;
    }
    if (listen(server_socket, 4096) < 0) {
        return 1;
    }

    while (1) {
        int *client_socket = malloc(sizeof(int));
        *client_socket = accept(server_socket, NULL, NULL);
        if (*client_socket >= 0) {
            pthread_t thread_id;
            pthread_create(&thread_id, NULL, handle_client, client_socket);
            pthread_detach(thread_id);
        } else {
            free(client_socket);
        }
    }
    return 0;
}
EOF

    gcc -O2 -pthread /app/mail_worker.c -o /app/mail_worker
    strip /app/mail_worker
    rm /app/mail_worker.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
