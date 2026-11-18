#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/native_module

    cat << 'EOF' > /home/user/native_module/processor.c
#include <stdlib.h>
#include <string.h>

static int active_allocations = 0;

int get_active_allocations() {
    return active_allocations;
}

char* process_string(const char* input) {
    if (!input) return NULL;
    int len = strlen(input);
    char* output = (char*)malloc(len + 1);
    if (!output) return NULL;
    active_allocations++;

    int j = 0;
    char last = '\0';
    for (int i = 0; i < len; i++) {
        if (input[i] != last) {
            output[j++] = input[i];
            last = input[i];
        }
    }
    output[j] = '\0';
    return output;
}

void free_string(char* ptr) {
    if (ptr) {
        free(ptr);
        active_allocations--;
    }
}
EOF

    cat << 'EOF' > /home/user/native_module/Makefile
CC=gcc
CFLAGS=-fPIC -Wall

all: libprocessor.so

processor.o: processor.c
	$(CC) $(CFLAGS) -c processor.c

# Missing flag to create a shared object properly
libprocessor.so: processor.o
	$(CC) -o libprocessor.so processor.o
EOF

    cat << 'EOF' > /home/user/inputs.txt
aaabbbccc
xxxyyyzzz
hellooo
builddd_eeengineeer
consecutiveee
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
