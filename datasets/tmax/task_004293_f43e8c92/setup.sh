#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/release

    cat << 'EOF' > /home/user/release/Makefile
all: release_vm

main.o: main.c
	gcc -c main.c

vm.o: vm.c
	gcc -c vm.c

# BUG: missing vm.o in the linking stage
release_vm: main.o vm.o
	gcc main.o -o release_vm

clean:
	rm -f *.o release_vm
EOF

    cat << 'EOF' > /home/user/release/vm.h
#ifndef VM_H
#define VM_H

void run_vm(const char* filename);

#endif
EOF

    cat << 'EOF' > /home/user/release/main.c
#include <stdio.h>
#include "vm.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <script.ops>\n", argv[0]);
        return 1;
    }
    run_vm(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/release/vm.c
#include "vm.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int state[256] = {0};

void run_vm(const char* filename) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        printf("Failed to open %s\n", filename);
        exit(1);
    }

    char op[10];
    char arg1, arg2;
    while(fscanf(f, "%s", op) != EOF) {
        if (strcmp(op, "SET") == 0) {
            fscanf(f, " %c", &arg1);
            state[(int)arg1] = 1;
        } else if (strcmp(op, "REQ") == 0) {
            fscanf(f, " %c %c", &arg1, &arg2);
            // BUG: logical error, fails if requirement is met instead of when it's missing
            if (state[(int)arg2] == 1) {
                printf("Dependency fail: %c needs %c\n", arg1, arg2);
                exit(1);
            }
        } else if (strcmp(op, "OUT") == 0) {
            fscanf(f, " %c", &arg1);
            printf("%c", arg1);
        }
    }
    printf("\n");
    fclose(f);
}
EOF

    cat << 'EOF' > /home/user/release/prod_deploy.ops
SET B
SET A
REQ C A
REQ C B
SET C
OUT A
OUT B
OUT C
SET D
REQ E D
SET E
OUT E
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
