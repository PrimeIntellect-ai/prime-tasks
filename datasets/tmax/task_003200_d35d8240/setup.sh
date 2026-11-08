#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vm.c
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int* data;
    int size;
    int capacity;
} Stack;

void push(Stack* s, int val) {
    if (s->size >= s->capacity) {
        s->capacity *= 2;
        // BUG: missing sizeof(int) in realloc
        s->data = realloc(s->data, s->capacity); 
    }
    s->data[s->size++] = val;
}

int pop(Stack* s) {
    if (s->size <= 0) return 0;
    return s->data[--s->size];
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    Stack s = {malloc(4 * sizeof(int)), 0, 4};
    unsigned char instr;
    while (fread(&instr, 1, 1, f) == 1) {
        if (instr == 0x01) { // PUSH
            int val;
            if (fread(&val, 4, 1, f) != 1) break;
            push(&s, val);
        } else if (instr == 0x02) { // ADD
            int a = pop(&s);
            int b = pop(&s);
            push(&s, a + b);
        } else if (instr == 0x03) { // PRINT
            printf("%d\n", pop(&s));
        }
    }
    free(s.data);
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
