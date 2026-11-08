#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc protobuf-compiler build-essential
    pip3 install pytest

    mkdir -p /app/libpld
    cat << 'EOF' > /app/libpld/pld.h
#include <stdint.h>
#include <stddef.h>

struct Pld {
    const uint8_t* code;
    size_t len;
};

struct Pld* parse_pld(const uint8_t* data, size_t data_len);
void free_pld(struct Pld* pld);
EOF

    cat << 'EOF' > /app/libpld/pld.c
#include "pld.h"
#include <stdlib.h>

struct Pld* parse_pld(const uint8_t* data, size_t data_len) {
    if (data_len < 4) return NULL;
    if (data[0] != 'P' || data[1] != 'L' || data[2] != 'D' || data[3] != '\0') return NULL;
    struct Pld* pld = (struct Pld*)malloc(sizeof(struct Pld));
    pld->code = data + 4;
    pld->len = data_len - 4;
    return pld;
}

void free_pld(struct Pld* pld) {
    if (pld) free(pld);
}
EOF

    cat << 'EOF' > /app/libpld/Makefile
all: libpld.a

pld.o: pld.c
	gcc -c pld.c -o pld.o

libpld.a: pld.o
	gcc -shared -o libpld.a pld.o

clean:
	rm -f pld.o libpld.a
EOF

    python3 -c '
import os

os.makedirs("/app/corpus/evil", exist_ok=True)
os.makedirs("/app/corpus/clean", exist_ok=True)

evil_payloads = [
    b"PLD\x00\x90\x0f\x05\x90",
    b"PLD\x00\xcd\x80\xcc",
    b"PLD\x00\x0f\x05",
    b"PLD\x00\x90\x90\xcd\x80",
    b"PLD\x00\xcc\x0f\x05\xcd\x80"
]

clean_payloads = [
    b"PLD\x00\x90\x90\x90",
    b"PLD\x00\x48\x31\xc0",
    b"PLD\x00\xcc\xcc\xcc",
    b"PLD\x00\xeb\xfe",
    b"PLD\x00\x0f\x1f\x00"
]

for i, p in enumerate(evil_payloads, 1):
    with open(f"/app/corpus/evil/{i}.pld", "wb") as f:
        f.write(p)

for i, p in enumerate(clean_payloads, 1):
    with open(f"/app/corpus/clean/{i}.pld", "wb") as f:
        f.write(p)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
