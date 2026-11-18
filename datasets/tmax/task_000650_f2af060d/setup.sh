#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemd
    cd /home/user/telemd

    cat << 'EOF' > queue.h
#ifndef QUEUE_H
#define QUEUE_H

#include <pthread.h>

typedef struct Node {
    int event_id;
    struct Node* next;
} Node;

extern Node* head;
extern pthread_mutex_t queue_mutex;

void enqueue_event(int id);
void process_events_recursive(Node* n);

#endif
EOF

    cat << 'EOF' > queue.c
#include <stdlib.h>
#include <stdio.h>
#include "queue.h"

Node* head = NULL;
pthread_mutex_t queue_mutex = PTHREAD_MUTEX_INITIALIZER;

void enqueue_event(int id) {
    Node* new_node = (Node*)malloc(sizeof(Node));
    new_node->event_id = id;
    new_node->next = NULL;

    // BUG: Missing mutex lock here causes race conditions and list corruption (cycles) under load
    if (head == NULL) {
        head = new_node;
    } else {
        Node* temp = head;
        while (temp->next != NULL) {
            temp = temp->next;
        }
        temp->next = new_node;
    }
}
EOF

    cat << 'EOF' > worker.c
#include <stdio.h>
#include "queue.h"

void process_events_recursive(Node* n) {
    // BUG: No cycle detection or depth limit. Will stack overflow if the list is cyclic.
    if (n == NULL) return;

    // Simulate processing
    int processed_id = n->event_id;

    process_events_recursive(n->next);
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include "queue.h"

#define NUM_THREADS 4
#define EVENTS_PER_THREAD 1000

void* producer(void* arg) {
    for (int i = 0; i < EVENTS_PER_THREAD; i++) {
        enqueue_event(rand() % 1000);
    }
    return NULL;
}

// Artificially inject a cycle for testing purposes to guarantee the crash if not fixed
void inject_cycle() {
    pthread_mutex_lock(&queue_mutex);
    if (head != NULL) {
        Node* temp = head;
        while (temp->next != NULL) {
            temp = temp->next;
        }
        temp->next = head; // Create cycle
    }
    pthread_mutex_unlock(&queue_mutex);
}

int main() {
    pthread_t threads[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_create(&threads[i], NULL, producer, NULL);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    inject_cycle();

    // This will stack overflow if the cycle isn't handled in worker.c
    process_events_recursive(head);

    printf("Processing complete.\n");
    return 0;
}
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-g -O0 -pthread -Wall

all: telemd

telemd: main.c queue.c worker.c
	$(CC) $(CFLAGS) -o telemd main.c queue.c worker.c

clean:
	rm -f telemd
EOF

    cat << 'EOF' > test_telemd.sh
#!/bin/bash
./telemd > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Tests passed!"
    exit 0
else
    echo "Tests failed! Service crashed."
    exit 1
fi
EOF

    chmod +x test_telemd.sh
    chown -R user:user /home/user/telemd
    chmod -R 777 /home/user
