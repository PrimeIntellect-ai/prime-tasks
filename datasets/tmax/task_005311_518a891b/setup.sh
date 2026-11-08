#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc make libc6-dev sqlite3
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/rle-c-1.0.0

    # Create rle.c with the bug
    cat << 'EOF' > /app/rle-c-1.0.0/rle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* rle_encode(const char* input) {
    if (!input) return NULL;
    int len = strlen(input);
    if (len == 0) {
        char* empty = malloc(1);
        empty[0] = '\0';
        return empty;
    }

    // BUG: Allocates insufficient memory for counts > 9
    char* output = malloc(len * 2 + 1);
    int out_idx = 0;

    for (int i = 0; i < len; i++) {
        int count = 1;
        while (i + 1 < len && input[i] == input[i+1]) {
            count++;
            i++;
        }
        out_idx += sprintf(output + out_idx, "%c%d", input[i], count);
    }
    output[out_idx] = '\0';
    return output;
}

void rle_free(char* ptr) {
    free(ptr);
}
EOF

    # Create rle.h
    cat << 'EOF' > /app/rle-c-1.0.0/rle.h
#ifndef RLE_H
#define RLE_H

char* rle_encode(const char* input);
void rle_free(char* ptr);

#endif
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/rle-c-1.0.0/Makefile
CC=gcc
CFLAGS=-Wall

all: librle.a

rle.o: rle.c
	$(CC) $(CFLAGS) -c rle.c

librle.a: rle.o
	$(CC) -o librle.a rle.o

clean:
	rm -f *.o *.a
EOF

    # Create service directory
    mkdir -p /home/user/service

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
