#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > vuln_bin.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

char *global_buffer = NULL;

void* cmd_ping(void *arg) {
    usleep(1000);
    return NULL;
}

void* cmd_alloc(void *arg) {
    if (global_buffer == NULL) {
        global_buffer = malloc(1024);
        if (global_buffer) {
            strcpy(global_buffer, "INITIALIZED");
        }
    }
    return NULL;
}

void* cmd_free(void *arg) {
    if (global_buffer != NULL) {
        free(global_buffer);
        // Vulnerability: Artificial race window before setting to NULL
        usleep(5000); 
        global_buffer = NULL;
    }
    return NULL;
}

void* cmd_process(void *arg) {
    usleep(2000); // Wait slightly to hit the race window from cmd_free
    if (global_buffer != NULL) {
        // Crash happens here if freed by another thread
        global_buffer[0] = 'X'; 
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    pthread_t threads[200];
    int t_count = 0;

    while (fgets(line, sizeof(line), f) && t_count < 200) {
        line[strcspn(line, "\n")] = 0;
        if (strcmp(line, "PING") == 0) {
            pthread_create(&threads[t_count++], NULL, cmd_ping, NULL);
        } else if (strcmp(line, "ALLOC") == 0) {
            pthread_create(&threads[t_count++], NULL, cmd_alloc, NULL);
            usleep(10000); // Ensure alloc finishes first
        } else if (strcmp(line, "FREE") == 0) {
            pthread_create(&threads[t_count++], NULL, cmd_free, NULL);
        } else if (strcmp(line, "PROCESS") == 0) {
            pthread_create(&threads[t_count++], NULL, cmd_process, NULL);
        }
    }

    for (int i = 0; i < t_count; i++) {
        pthread_join(threads[i], NULL);
    }

    fclose(f);
    return 0;
}
EOF

    gcc -g -pthread vuln_bin.c -o vuln_bin

    cat << 'EOF' > capture.txt
PING
PING
PING
PING
PING
PING
PING
ALLOC
PING
PING
PING
PING
PING
PING
PING
PING
FREE
PING
PING
PROCESS
PING
PING
PING
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
