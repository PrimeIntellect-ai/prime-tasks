#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make file
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > requirements.txt
fastapi==0.103.1
pydantic==1.8.2
pytest==7.4.2
requests==2.31.0
uvicorn==0.23.2
EOF

    cat << 'EOF' > vm.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int execute_vm(const char* instructions) {
    int accumulator = 0;
    char* copy = strdup(instructions);
    char* token = strtok(copy, "\n");

    while (token != NULL) {
        if (strncmp(token, "ADD ", 4) == 0) {
            accumulator += atoi(token + 4);
        } else if (strncmp(token, "SUB ", 4) == 0) {
            accumulator -= atoi(token + 4);
        } else if (strncmp(token, "RET", 3) == 0) {
            break;
        }
        token = strtok(NULL, "\n");
    }

    free(copy);
    return accumulator;
}
EOF

    cat << 'EOF' > Makefile
all: vm

vm: vm.c
	gcc -o libvm.so vm.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
