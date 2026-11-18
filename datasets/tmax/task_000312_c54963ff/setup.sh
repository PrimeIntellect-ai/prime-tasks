#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/build

    cat << 'EOF' > /home/user/build/crunch.c
#include <stdlib.h>
#include <stdio.h>

void process_array(int* data, int size) {
    int* temp = (int*)malloc(size * sizeof(int));
    if (!temp) return;
    for(int i=0; i<size; i++) {
        temp[i] = data[i] * 2;
        data[i] = temp[i] / 2;
    }
    // INTENTIONAL LEAK: missing deallocation
}
EOF

    cat << 'EOF' > /home/user/build/Makefile
CC=gcc

all: debug

debug: crunch.c
	$(CC) -g -shared -fPIC -o libcrunch.so crunch.c

release: crunch.c
	$(CC) -O3 -o libcrunch.so crunch.c 
	# BROKEN: missing flags for shared library
EOF

    cat << 'EOF' > /home/user/build/test_run.py
import ctypes
import os

def main():
    lib_path = os.path.abspath('./libcrunch.so')
    if not os.path.exists(lib_path):
        print("Library not found!")
        return

    lib = ctypes.CDLL(lib_path)
    lib.process_array.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    lib.process_array.restype = None

    size = 1000
    IntArray = ctypes.c_int * size

    for _ in range(50000):
        data = IntArray(*range(size))
        lib.process_array(data, size)

    print("DONE")

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
