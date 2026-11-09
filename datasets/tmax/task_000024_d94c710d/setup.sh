#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make git
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/fast_profiler/src
mkdir -p /home/user/fast_profiler/tests
cd /home/user/fast_profiler

cat << 'EOF' > src/telemetry.h
#ifndef TELEMETRY_H
#define TELEMETRY_H

int telemetry_init();

#endif
EOF

cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Werror -Wimplicit-function-declaration -Isrc

all: libtelemetry.a

libtelemetry.a: telemetry.o
	ar rcs libtelemetry.a telemetry.o

telemetry.o: src/telemetry.c
	$(CC) $(CFLAGS) -c src/telemetry.c -o telemetry.o

clean:
	rm -f *.o *.a tests/*.o test_bin
EOF

git init
git config user.email "perf@example.com"
git config user.name "Perf Engineer"

# Commit 1
cat << 'EOF' > src/telemetry.c
#include "telemetry.h"
#include <stdio.h>

int telemetry_init() {
    printf("Telemetry initialized.\n");
    return 0;
}
EOF
git add .
git commit -m "Initial commit"

# Commit 2 (contains the secret)
cat << 'EOF' > src/telemetry.c
#include "telemetry.h"
#include <stdio.h>

#define TELEMETRY_TOKEN "TKN-883A-29B1"

int telemetry_init() {
    printf("Telemetry initialized with %s.\n", TELEMETRY_TOKEN);
    return 0;
}
EOF
git add src/telemetry.c
git commit -m "Add telemetry token"

# Commit 3 (removes secret, introduces bug missing stdlib.h)
cat << 'EOF' > src/telemetry.c
#include "telemetry.h"
#include <stdio.h>

int telemetry_init() {
    char* token = getenv("TELEMETRY_TOKEN");
    if (token == NULL) {
        return -1;
    }
    printf("Telemetry initialized with token.\n");
    return 0;
}
EOF
git add src/telemetry.c
git commit -m "Read token from env to hide secret"

chown -R user:user /home/user/fast_profiler
chmod -R 777 /home/user
