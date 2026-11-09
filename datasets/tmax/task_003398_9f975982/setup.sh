#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make nginx netcat-openbsd socat gawk curl binutils
pip3 install pytest

mkdir -p /app/logs /home/user/workspace/audit

# 1. Create the stripped binary /app/evaluator
cat << 'EOF' > /tmp/evaluator.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char buf[256];
    if (fgets(buf, sizeof(buf), stdin) != NULL) {
        int a, b;
        char op;
        if (sscanf(buf, "%d %c %d", &a, &op, &b) == 3) {
            if (op == '+') printf("%d\n", a + b);
            else if (op == '-') printf("%d\n", a - b);
            else if (op == '*') printf("%d\n", a * b);
            else printf("ERR\n");
        } else {
            printf("PARSE_ERR\n");
        }
    }
    return 0;
}
EOF
gcc -O2 /tmp/evaluator.c -o /app/evaluator
strip /app/evaluator
chmod +x /app/evaluator

# 2. Create the C source and broken Makefile for audit
cat << 'EOF' > /home/user/workspace/audit/audit.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h> // Requires -lpthread

void* handle_client(void* arg) {
    int sock = *(int*)arg;
    free(arg);
    char buffer[1024];
    int n = read(sock, buffer, sizeof(buffer)-1);
    if (n > 0) {
        buffer[n] = '\0';
        FILE *f = fopen("/tmp/audit.log", "a");
        if (f) {
            fprintf(f, "AUDIT: %s\n", buffer);
            fclose(f);
        }
    }
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
    address.sin_port = htons(9002);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

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

cat << 'EOF' > /home/user/workspace/audit/Makefile
# Broken Makefile - missing pthread and syntax issue
all: audit

audit: audit.o
	gcc audit.o -o audit

audit.o: audit.c
	gcc -c audit.c
EOF

# 3. Create log files for reconciliation
cat << 'EOF' > /app/logs/server_a.log
192.168.1.5 - GET /index.html
10.0.0.2 - POST /login
192.168.1.10 - GET /assets/style.css
EOF

cat << 'EOF' > /app/logs/server_b.log
10.0.0.2 - POST /login
172.16.0.4 - GET /api/data
192.168.1.5 - GET /index.html
10.1.1.1 - DELETE /api/data/1
EOF

cat << 'EOF' > /app/logs/baseline.log
10.0.0.2 - POST /login
10.1.1.1 - DELETE /api/data/1
172.16.0.4 - GET /api/data
192.168.1.5 - GET /index.html
192.168.1.10 - GET /assets/style.css
192.168.1.20 - GET /unknown
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /app/logs /home/user/workspace/audit
chmod -R 777 /home/user
