#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential
    pip3 install pytest

    mkdir -p /home/user/websec_port
    cd /home/user/websec_port

    cat << 'EOF' > polyhash.h
#ifndef POLYHASH_H
#define POLYHASH_H

unsigned int validate_token(const char* token);

#endif
EOF

    cat << 'EOF' > polyhash.c
#include "polyhash.h"
#include <string.h>

// Simple polynomial rolling hash checksum
unsigned int validate_token(const char* token) {
    unsigned int hash = 0;
    unsigned int p = 31;
    unsigned int m = 1e9 + 9;
    unsigned int p_pow = 1;

    for (int i = 0; i < strlen(token); i++) {
        hash = (hash + (token[i] - 'a' + 1) * p_pow) % m;
        p_pow = (p_pow * p) % m;
    }

    // For our websec scenario, tokens with hash % 1337 == 42 are considered valid.
    if (hash % 1337 == 42) {
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: libpolyhash.a

libpolyhash.a: polyhash.o
	ar rcs libpolyhash.a polyhash.o

polyhash.o: polyhash.c
	gcc -c polyhash.c -o polyhash.o

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > main.go
package main

/*
#cgo CFLAGS: -I.
// BUG: Missing LDFLAGS to link the static library. The agent needs to add:
// #cgo LDFLAGS: -L. -lpolyhash
#include <stdlib.h>
#include "polyhash.h"
*/
import "C"
import (
	"bufio"
	"fmt"
	"os"
	"unsafe"
)

func isValid(token string) bool {
	cToken := C.CString(token)
	defer C.free(unsafe.Pointer(cToken))

	result := C.validate_token(cToken)
	return result == 1
}

func main() {
	// TODO: Implement concurrent processing of tokens.txt using goroutines
	// and write valid tokens to valid_tokens.txt
}
EOF

    cat << 'EOF' > generate_tokens.py
import random
import string

def poly_hash(token):
    h = 0
    p = 31
    m = int(1e9 + 9)
    p_pow = 1
    for char in token:
        h = (h + (ord(char) - ord('a') + 1) * p_pow) % m
        p_pow = (p_pow * p) % m
    return h

random.seed(12345)
with open("/home/user/websec_port/tokens.txt", "w") as f:
    for _ in range(5000):
        # Generate random lowercase strings
        length = random.randint(10, 20)
        token = ''.join(random.choice(string.ascii_lowercase) for _ in range(length))
        f.write(token + "\n")
EOF

    python3 generate_tokens.py
    rm generate_tokens.py

    cd /home/user/websec_port
    go mod init websec_port

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
