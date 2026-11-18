#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/router_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse_params(char *query) {
    if (strlen(query) == 0) {
        char *crash = NULL;
        *crash = 1; // Segfault if ? present but no parameters
    }
    char *token = strtok(query, "&");
    while (token != NULL) {
        char *eq = strchr(token, '=');
        if (eq) {
            *eq = '\0';
            char key[32];
            strcpy(key, token); // Buffer overflow if key > 32
        }
        token = strtok(NULL, "&");
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *url = argv[1];

    char *path = malloc(256);
    char *qmark = strchr(url, '?');
    if (qmark) {
        int path_len = qmark - url;
        memcpy(path, url, path_len); // Heap overflow if path > 256
        path[path_len] = '\0';
        parse_params(qmark + 1);
    } else {
        strcpy(path, url); // Heap overflow if path > 256
    }
    printf("Path: %s\n", path);
    free(path);
    return 0;
}
EOF

    gcc -fno-stack-protector -o /app/router_engine_stripped /app/router_engine.c
    strip /app/router_engine_stripped
    rm /app/router_engine.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
