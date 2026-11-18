#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/polybuild/legacy
    mkdir -p /home/user/polybuild/src/polybuild
    touch /home/user/polybuild/src/polybuild/__init__.py

    cat << 'EOF' > /home/user/polybuild/legacy/ring_buffer.c
#include <stdbool.h>

typedef struct {
    int *buffer;
    int head;
    int tail;
    int max;
    bool full;
} ring_buffer_t;

// Implementation overwrites oldest data when full
void ring_buffer_push(ring_buffer_t *rb, int data) {
    rb->buffer[rb->head] = data;
    if (rb->full) {
        rb->tail = (rb->tail + 1) % rb->max;
    }
    rb->head = (rb->head + 1) % rb->max;
    rb->full = rb->head == rb->tail;
}

int ring_buffer_pop(ring_buffer_t *rb) {
    if (!rb->full && (rb->head == rb->tail)) {
        return -1; // empty indicator
    }
    int data = rb->buffer[rb->tail];
    rb->full = false;
    rb->tail = (rb->tail + 1) % rb->max;
    return data;
}
EOF

    cat << 'EOF' > /home/user/polybuild/pyproject.toml
[build-system]
# missing requires and build-backend

[project]
name = "polyb"
version = "0.0.1"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
