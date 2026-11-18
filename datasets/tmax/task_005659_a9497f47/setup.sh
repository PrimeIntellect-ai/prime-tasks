#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_records.py
import struct

records = [
    (101, 500, 500),
    (102, 1000, 300),
    (103, 1000, 337), # Target
    (104, 2000, 100),
]

with open('/home/user/records.bin', 'wb') as f:
    for r in records:
        f.write(struct.pack('<III', *r))
EOF

    python3 /home/user/create_records.py
    rm /home/user/create_records.py

    cat << 'EOF' > /home/user/process.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct Node {
    uint32_t id;
    uint32_t a;
    uint32_t b;
    struct Node* next;
} Node;

int main() {
    FILE* fp = fopen("/home/user/records.bin", "rb");
    if (!fp) return 1;

    Node* head = NULL;
    Node* tail = NULL;

    // BUG 1: feof() pattern reads the last record twice or reads garbage at EOF
    while (!feof(fp)) {
        Node* n = (Node*)malloc(sizeof(Node));
        fread(&n->id, sizeof(uint32_t), 1, fp);
        fread(&n->a, sizeof(uint32_t), 1, fp);
        fread(&n->b, sizeof(uint32_t), 1, fp);

        n->next = NULL;
        if (!head) {
            head = n;
            tail = n;
        } else {
            tail->next = n;
            tail = n;
        }
    }
    fclose(fp);

    // Evaluate constraints
    Node* curr = head;
    uint32_t target_id = 0;
    while (curr) {
        if (curr->a + curr->b == 1337) {
            target_id = curr->id;
        }
        curr = curr->next;
    }

    printf("%u\n", target_id);

    // BUG 2: Missing free() loop

    return 0;
}
EOF

    chmod -R 777 /home/user
