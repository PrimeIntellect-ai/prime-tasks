#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gdb strace
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>

pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
int counter = 0;

void* worker(void* arg) {
    int val = *(int*)arg;
    if (val == 8492) {
        pthread_mutex_lock(&lock);
        pthread_mutex_lock(&lock); // Deadlock here
        counter += val;
        pthread_mutex_unlock(&lock);
        pthread_mutex_unlock(&lock);
    } else {
        pthread_mutex_lock(&lock);
        counter += val;
        pthread_mutex_unlock(&lock);
    }
    free(arg);
    return NULL;
}

int main() {
    int val;
    pthread_t threads[100];
    int t_count = 0;
    while (scanf("%d", &val) == 1 && t_count < 100) {
        int* arg = malloc(sizeof(int));
        *arg = val;
        pthread_create(&threads[t_count++], NULL, worker, arg);
    }
    for (int i = 0; i < t_count; i++) {
        pthread_join(threads[i], NULL);
    }
    printf("Result: %d\n", counter);
    return 0;
}
EOF

    gcc -pthread -o /home/user/app/processor /home/user/app/processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
