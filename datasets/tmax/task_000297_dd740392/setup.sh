#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/vm_project/src
    mkdir -p /home/user/vm_project/tests

    cat << 'EOF' > /home/user/vm_project/Makefile
CC = gcc
CFLAGS = -Wall -Wextra -Werror

all: simple_vm

simple_vm: src/main.c src/vm.c
	$(CC) $(CFLAGS) -o simple_vm src/main.c src/vm.c

clean:
	rm -f simple_vm
EOF

    cat << 'EOF' > /home/user/vm_project/src/vm.h
#ifndef VM_H
#define VM_H

#define MAX_STACK 10

typedef struct {
    int stack[MAX_STACK];
    int sp;
} VM;

void vm_init(VM *vm);
void vm_push(VM *vm, int val);
int vm_pop(VM *vm);

#endif
EOF

    cat << 'EOF' > /home/user/vm_project/src/vm.c
#include "vm.h"
// Bug 1: Missing standard library includes for exit, printf, etc. (causes -Werror to fail)

void vm_init(VM *vm) {
    vm->sp = 0;
}

void vm_push(VM *vm, int val) {
    // Bug 2: No stack overflow check
    vm->stack[vm->sp++] = val;
}

int vm_pop(VM *vm) {
    // Bug 3: No stack underflow check
    return vm->stack[--vm->sp];
}
EOF

    cat << 'EOF' > /home/user/vm_project/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vm.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("Usage: %s <file.asm>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        printf("Error opening file\n");
        return 1;
    }

    VM vm;
    vm_init(&vm);

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "PUSH", 4) == 0) {
            int val;
            sscanf(line, "PUSH %d", &val);
            vm_push(&vm, val);
        } else if (strncmp(line, "ADD", 3) == 0) {
            int a = vm_pop(&vm);
            int b = vm_pop(&vm);
            vm_push(&vm, a + b);
        } else if (strncmp(line, "PRINT", 5) == 0) {
            int val = vm_pop(&vm);
            printf("%d\n", val);
        }
    }

    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_normal.asm
PUSH 5
PUSH 10
ADD
PRINT
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_normal.expected
15
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_overflow.asm
PUSH 1
PUSH 2
PUSH 3
PUSH 4
PUSH 5
PUSH 6
PUSH 7
PUSH 8
PUSH 9
PUSH 10
PUSH 11
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_overflow.expected
Error: Stack Overflow
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_underflow.asm
PUSH 5
ADD
EOF

    cat << 'EOF' > /home/user/vm_project/tests/test_underflow.expected
Error: Stack Underflow
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
