#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make python3-yaml
    pip3 install pytest

    # Create directories
    mkdir -p /app/c-string-hasher
    mkdir -p /home/user/repo/.github/workflows
    mkdir -p /opt/oracle

    # Create C files with circular dependency
    cat << 'EOF' > /app/c-string-hasher/hash.h
#ifndef HASH_H
#define HASH_H

#include "util.h"

struct HashContext {
    int state;
};

char* compute_hash(const char* input);
void free_hash_result(char* ptr);

#endif
EOF

    cat << 'EOF' > /app/c-string-hasher/util.h
#ifndef UTIL_H
#define UTIL_H

#include "hash.h"

struct Config {
    struct HashContext* ctx;
    int flags;
};

void init_config(struct Config* cfg);

#endif
EOF

    cat << 'EOF' > /app/c-string-hasher/hash.c
#include <stdlib.h>
#include <string.h>
#include "hash.h"
#include "util.h"

char* compute_hash(const char* input) {
    if (!input) return NULL;
    int len = strlen(input);
    char* out = malloc(len + 1);
    if (!out) return NULL;
    for (int i = 0; i < len; i++) {
        out[i] = input[i] ^ 0x2A;
    }
    out[len] = '\0';
    return out;
}

void free_hash_result(char* ptr) {
    free(ptr);
}

void init_config(struct Config* cfg) {
    cfg->flags = 1;
}
EOF

    cat << 'EOF' > /app/c-string-hasher/Makefile
CC = gcc
CFLAGS = -fPIC -Wall -Wextra -Werror
LDFLAGS = -shared

all: libhasher.so

libhasher.so: hash.c hash.h util.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ hash.c

clean:
	rm -f libhasher.so
EOF

    # Create Oracle
    cat << 'EOF' > /opt/oracle/process_oracle.py
import sys

def compute_hash(input_str):
    return "".join(chr(ord(c) ^ 0x2A) for c in input_str)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(compute_hash(sys.argv[1]), end="")
EOF
    chmod +x /opt/oracle/process_oracle.py

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
