#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/repo

    # Create oracle_bin
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(size);
    fread(buf, 1, size, f);
    fclose(f);

    for (long i = 0; i < size / 2; i++) {
        unsigned char tmp = buf[i] ^ 0x4B;
        buf[i] = buf[size - 1 - i] ^ 0x4B;
        buf[size - 1 - i] = tmp;
    }
    if (size % 2 != 0) {
        buf[size / 2] ^= 0x4B;
    }

    fwrite(buf, 1, size, stdout);
    free(buf);
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_bin
    chmod +x /app/oracle_bin

    # Create spec.png
    convert -size 500x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'The magic transformation constant is 0x4B.'" /app/spec.png

    # Create repo files
    cat << 'EOF' > /home/user/repo/Makefile
all: libworker.so

libworker.so: worker.go math.s
	go build -buildmode=c-shared -o libworker.so worker.go
EOF

    cat << 'EOF' > /home/user/repo/math.s
.global apply_transform
apply_transform:
    mov %edi, %eax
    xor %esi, %eax
    ret
EOF

    cat << 'EOF' > /home/user/repo/worker.go
package main

import "C"
import "sync"

//export ProcessChunk
func ProcessChunk(data *C.char, length C.int, key C.int) {
    var wg sync.WaitGroup
    wg.Add(1)
    go func() {
        // Deadlock here intentionally
        wg.Wait()
    }()
    wg.Wait()
}

func main() {}
EOF

    cat << 'EOF' > /home/user/repo/main.py
import sys
import ctypes

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    # Missing ctypes setup
    lib = ctypes.CDLL("./libworker.so")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
