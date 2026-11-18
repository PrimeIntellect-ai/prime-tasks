#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace/src

    cat << 'EOF' > /home/user/workspace/src/utils.h
#ifndef UTILS_H
#define UTILS_H
int calculate_score(int length, int multiplier);
#endif
EOF

    cat << 'EOF' > /home/user/workspace/src/utils.c
#include "utils.h"
int calculate_score(int length, int multiplier) {
    return length * multiplier;
}
EOF

    cat << 'EOF' > /home/user/workspace/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "utils.h"

int main() {
    char* config_path = getenv("CONFIG_PATH");
    if (!config_path) {
        fprintf(stderr, "Error: CONFIG_PATH not set\n");
        return 1;
    }

    FILE* f = fopen(config_path, "r");
    if (!f) {
        fprintf(stderr, "Error: Cannot open config file\n");
        return 1;
    }

    int multiplier = 1;
    char line[256];
    if (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MULTIPLIER=", 11) == 0) {
            multiplier = atoi(line + 11);
        }
    }
    fclose(f);

    int length = 0;
    int ch;
    while ((ch = fgetc(stdin)) != EOF) {
        length++;
    }

    printf("Result: %d\n", calculate_score(length, multiplier));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/Makefile
CC=gcc
CFLAGS=-I./src

all: processor

processor: src/main.o src/utils.o processor
	$(CC) -o processor src/main.o src/utils.o

src/main.o: src/main.c src/main.o
	$(CC) $(CFLAGS) -c src/main.c -o src/main.o

src/utils.o: src/utils.c src/utils.h
	$(CC) $(CFLAGS) -c src/utils.c -o src/utils.o

clean:
	rm -f src/*.o processor
EOF

    chmod -R 777 /home/user
