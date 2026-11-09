#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/math_project
    cd /home/user/math_project

    cat << 'EOF' > Makefile
all: calc

calc: calc.c
	gcc -o calc calc.c
EOF

    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#define MAX_LINES 10000

typedef struct {
    int id;
    char op[4];
    int a;
    int b;
} Task;

Task tasks[MAX_LINES];
int task_count = 0;
long long global_total = 0;
pthread_mutex_t lock;

void* worker(void* arg) {
    int thread_id = *(int*)arg;
    for (int i = thread_id; i < task_count; i += 4) {
        long long res = 0;
        if (strcmp(tasks[i].op, "ADD") == 0) res = tasks[i].a + tasks[i].b;
        else if (strcmp(tasks[i].op, "SUB") == 0) res = tasks[i].a - tasks[i].b;
        else if (strcmp(tasks[i].op, "MUL") == 0) res = tasks[i].a * tasks[i].b;
        else if (strcmp(tasks[i].op, "DIV") == 0) {
            res = tasks[i].a / tasks[i].b;
        }

        pthread_mutex_lock(&lock);
        global_total += res;
        pthread_mutex_unlock(&lock);
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    while (fscanf(f, "%d %3s %d %d", &tasks[task_count].id, tasks[task_count].op, &tasks[task_count].a, &tasks[task_count].b) == 4) {
        task_count++;
    }
    fclose(f);

    pthread_mutex_init(&lock, NULL);
    pthread_t threads[4];
    int tids[4] = {0, 1, 2, 3};

    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, worker, &tids[i]);
    }

    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("Total: %lld\n", global_total);
    return 0;
}
EOF

    python3 -c '
import random
random.seed(42)
with open("data.txt", "w") as f:
    for i in range(1000):
        if i == 425:
            f.write(f"{i} DIV 50 0\n")
        else:
            op = random.choice(["ADD", "SUB", "MUL", "DIV"])
            a = random.randint(1, 100)
            b = random.randint(1, 10)
            f.write(f"{i} {op} {a} {b}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
