#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc make patch
    pip3 install pytest

    mkdir -p /app/libmathcheck-1.2.4
    mkdir -p /app/patches

    cat << 'EOF' > /app/libmathcheck-1.2.4/mathcheck.h
#ifndef MATHCHECK_H
#define MATHCHECK_H
#include <stdint.h>
#include <stddef.h>

uint32_t calculate_parity(const uint8_t* data, size_t len);

#endif
EOF

    cat << 'EOF' > /app/libmathcheck-1.2.4/mathcheck.c
#include "mathcheck.h"

uint32_t calculate_parity(const uint8_t* data, size_t len) {
    uint32_t parity;
    for (size_t i = 0; i <= len; i++) {
        parity ^= data[i];
    }
    return parity;
}
EOF

    cat << 'EOF' > /app/libmathcheck-1.2.4/Makefile
CC=gcc
CFLAGS=-Wall -O2

all: libmathcheck.a

libmathcheck.a: mathcheck.o
	ar rcs libmathcheck.a mathcheck.o

mathcheck.o: mathcheck.c
	$(CC) $(CFLAGS) -c mathcheck.c -o mathcheck.o

clean:
	rm -f *.o *.a *.so
EOF

    cat << 'EOF' > /app/patches/CVE-2023-mathcheck.patch
--- mathcheck.c
+++ mathcheck.c
@@ -2,6 +2,9 @@

 uint32_t calculate_parity(const uint8_t* data, size_t len) {
+    if (data == 0 || len == 0) {
+        return 0;
+    }
     uint32_t parity;
     for (size_t i = 0; i <= len; i++) {
         parity ^= data[i];
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
