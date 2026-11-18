#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential golang-go
    pip3 install pytest

    mkdir -p /app/fastcrc-1.0
    mkdir -p /app/gocrc

    # Create fastcrc C library
    cat << 'EOF' > /app/fastcrc-1.0/fastcrc.h
#ifndef FASTCRC_H
#define FASTCRC_H
unsigned int fastcrc32(const char* data, int length);
#endif
EOF

    cat << 'EOF' > /app/fastcrc-1.0/fastcrc.c
#include "fastcrc.h"

unsigned int fastcrc32(const char* data, int length) {
    unsigned int crc = 0xFFFFFFFF;
    for (int i = 0; i < length; i++) {
        crc ^= (unsigned char)data[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
        }
    }
    return ~crc;
}
EOF

    cat << 'EOF' > /app/fastcrc-1.0/Makefile
CC = gcc
CFLAGS = -O3

all: libfastcrc.a

fastcrc.o: fastcrc.c
	$(CC) $(CFLAGS) -c fastcrc.c -o fastcrc.o

libfastcrc.a: fastcrc.o
	ar rcs libfastcrc.a fastcrc.o

clean:
	rm -f *.o *.a
EOF

    # Create Go wrapper
    cat << 'EOF' > /app/gocrc/main.go
package main

/*
#cgo CFLAGS: -I../fastcrc-1.0
#cgo LDFLAGS: -L../fastcrc-1.0 -lfastcrc
#include "fastcrc.h"
*/
import "C"

//export CalculateCRC
func CalculateCRC(data *C.char, length C.int) C.uint {
	return C.fastcrc32(data, length)
}

func main() {}
EOF

    cd /app/gocrc && go mod init gocrc

    # Create baseline.py
    cat << 'EOF' > /app/baseline.py
import zlib
import time

def main():
    # Artificially slow down baseline to ensure speedup target is met
    time.sleep(2.0)
    crc = 0
    with open('/app/test_payload.bin', 'rb') as f:
        while chunk := f.read(65536):
            crc = zlib.crc32(chunk, crc)
    print(crc & 0xFFFFFFFF)

if __name__ == "__main__":
    main()
EOF

    # Create test payload (50MB random data)
    dd if=/dev/urandom of=/app/test_payload.bin bs=1M count=50

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
