#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx netcat-openbsd curl
    pip3 install pytest

    mkdir -p /app/nginx
    mkdir -p /app/vendor/simple-c-server-1.0

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /app/vendor/simple-c-server-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>

void* dummy_thread(void* arg) {
    return NULL;
}

int main() {
    char* tz = getenv("TZ");
    if (!tz || strcmp(tz, "Etc/UTC") != 0) {
        fprintf(stderr, "Assertion failed: TZ must be Etc/UTC\n");
        exit(1);
    }

    pthread_t t;
    pthread_create(&t, NULL, dummy_thread, NULL);
    pthread_join(t, NULL);

    sleep(3);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(1);
    }

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(1);
    }

    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;
        char buffer[1024] = {0};
        read(client_fd, buffer, 1024);
        char *response = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nStatus: OK\n";
        write(client_fd, response, strlen(response));
        close(client_fd);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/vendor/simple-c-server-1.0/Makefile
CC=gcc
CFLAGS=-O2
LDFLAGS=-lthred

server: main.c
	$(CC) $(CFLAGS) main.c -o server $(LDFLAGS)
EOF

    cat << 'EOF' > /app/ci_runner.sh
#!/bin/bash
cd /app/vendor/simple-c-server-1.0
make

# Start backend
./server &

# Start Nginx
nginx -c /app/nginx/nginx.conf &

wait
EOF
    chmod +x /app/ci_runner.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
