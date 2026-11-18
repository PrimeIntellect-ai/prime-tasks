#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/uptime_agent.c
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int *status_ptr = NULL;

void* check_health(void* arg) {
    for (int i = 0; i < 1000; i++) {
        if (status_ptr == NULL) {
            status_ptr = malloc(sizeof(int));
            *status_ptr = 1;
        }
    }
    return NULL;
}

void* report_status(void* arg) {
    for (int i = 0; i < 1000; i++) {
        if (status_ptr != NULL) {
            free(status_ptr);
            status_ptr = NULL;
        }
    }
    return NULL;
}

int main() {
    pthread_t t1, t2;
    while(1) {
        pthread_create(&t1, NULL, check_health, NULL);
        pthread_create(&t2, NULL, report_status, NULL);
        pthread_join(t1, NULL);
        pthread_join(t2, NULL);
    }
    return 0;
}
EOF

    gcc -pthread -O0 -o /home/user/uptime_agent /tmp/uptime_agent.c
    rm /tmp/uptime_agent.c

    chmod -R 777 /home/user
