#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils curl
    pip3 install pytest

    mkdir -p /app/minilogd-1.0/src
    mkdir -p /app/minilogd-1.0/include
    mkdir -p /app/minilogd-1.0/lib

    # Create auth.h
    cat << 'EOF' > /app/minilogd-1.0/include/auth.h
#ifndef AUTH_H
#define AUTH_H
int validate_token(const char* token);
#endif
EOF

    # Create auth.c and compile it to libauth.so
    cat << 'EOF' > /tmp/auth.c
#include <string.h>
int validate_token(const char* token) {
    return strcmp(token, "s3cr3t_0ps_t0k3n_99") == 0;
}
EOF
    gcc -shared -fPIC -o /app/minilogd-1.0/lib/libauth.so /tmp/auth.c
    rm /tmp/auth.c

    # Create src/db.c
    cat << 'EOF' > /app/minilogd-1.0/src/db.c
#include <string.h>

struct Log {
    char level[16];
    char app[32];
    char msg[128];
};

struct Log logs[1000];
int log_count = 0;

void add_log(const char* level, const char* app, const char* msg) {
    if (log_count < 1000) {
        strncpy(logs[log_count].level, level, 15);
        strncpy(logs[log_count].app, app, 31);
        strncpy(logs[log_count].msg, msg, 127);
        log_count++;
    }
}

int match_log(int index, const char* filter_level) {
    // BUG: bitwise AND instead of strcmp
    if (logs[index].level[0] & filter_level[0]) {
        return 1;
    }
    return 0;
}
EOF

    # Create src/query.c
    cat << 'EOF' > /app/minilogd-1.0/src/query.c
#include <stdio.h>

void parse_expr(const char* expr) {
    while (*expr) {
        if (*expr == '(') {
            expr++;
        } else if (*expr == ')') {
            // BUG: missing pointer increment causing infinite recursion/loop
            // expr++; 
        } else {
            expr++;
        }
    }
}
EOF

    # Create src/main.c
    cat << 'EOF' > /app/minilogd-1.0/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "auth.h"

extern void add_log(const char*, const char*, const char*);
extern int match_log(int, const char*);
extern void parse_expr(const char*);

void* tcp_worker(void* arg) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while(1) {
        int client_socket = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);
        char level[16], app[32], msg[128];
        if (sscanf(buffer, "[%15[^]]] app=%31s msg=%127[^\n]", level, app, msg) == 3) {
            add_log(level, app, msg);
        }
        close(client_socket);
    }
    return NULL;
}

void* http_worker(void* arg) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while(1) {
        int client_socket = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);

        char* auth = strstr(buffer, "Authorization: Bearer ");
        if (auth) {
            char token[64];
            sscanf(auth, "Authorization: Bearer %63s", token);
            if (!validate_token(token)) {
                char* res = "HTTP/1.1 401 Unauthorized\r\n\r\n";
                write(client_socket, res, strlen(res));
                close(client_socket);
                continue;
            }
        } else {
            char* res = "HTTP/1.1 401 Unauthorized\r\n\r\n";
            write(client_socket, res, strlen(res));
            close(client_socket);
            continue;
        }

        char* q = strstr(buffer, "GET /query?q=");
        if (q) {
            char query[128];
            sscanf(q, "GET /query?q=%127s", query);
            char* space = strchr(query, ' ');
            if (space) *space = '\0';

            parse_expr(query);

            char req_level[16] = {0};
            char* l = strstr(query, "level=");
            if (l) {
                sscanf(l, "level=%15[^)]", req_level);
            }

            char response[4096];
            strcpy(response, "HTTP/1.1 200 OK\r\n\r\n");

            extern int log_count;
            extern struct Log { char level[16]; char app[32]; char msg[128]; } logs[];

            for(int i=0; i<log_count; i++) {
                if (match_log(i, req_level)) {
                    char line[256];
                    sprintf(line, "[%s] app=%s msg=%s\n", logs[i].level, logs[i].app, logs[i].msg);
                    strcat(response, line);
                }
            }
            write(client_socket, response, strlen(response));
        }
        close(client_socket);
    }
    return NULL;
}

int main() {
    pthread_t t1, t2;
    pthread_create(&t1, NULL, tcp_worker, NULL);
    pthread_create(&t2, NULL, http_worker, NULL);
    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /app/minilogd-1.0/Makefile
all: minilogd

minilogd: src/main.c src/db.c src/query.c
	gcc -o minilogd src/main.c src/db.c src/query.c -Iinclude -Llib -lauth -lpthread -Wl,-rpath=$(PWD)/lib

clean:
	rm -f minilogd
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
