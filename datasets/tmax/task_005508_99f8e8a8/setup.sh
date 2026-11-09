#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/sysproj
    cd /home/user/sysproj

    cat << 'EOF' > libring.h
#ifndef LIBRING_H
#define LIBRING_H
void rb_init();
void rb_push(int val);
int rb_pop();
void rb_dump();
#endif
EOF

    cat << 'EOF' > libring.c
#include <stdio.h>
#include "libring.h"

int buffer[100];
int head = 0;
int tail = 0;

void rb_init() {
    head = 0;
    tail = 0;
}

void rb_push(int val) {
    buffer[head++] = val;
}

int rb_pop() {
    return buffer[tail++];
}

// Missing conditionally compiled rb_dump()
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall

all: libring.so

libring.so: libring.o
	$(CC) -shared -o libring.so libring.o

libring.o: libring.c
	$(CC) $(CFLAGS) -c libring.c

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > test_suite.rb
# Ruby pseudo-code for testing the library
# This is meant to guide the Python implementation
puts "Loading library..."
# load libring.so
# rb_init()
# rb_push(10)
# rb_push(20)
# val = rb_pop()
# puts "Popped: #{val}"
# rb_dump()
EOF

    # Create copies for diffing later if the agent forgets to backup
    cp libring.c libring.c.orig
    cp Makefile Makefile.orig

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
