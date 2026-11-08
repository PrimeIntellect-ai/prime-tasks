#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go gcc make libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project

cat << 'EOF' > /home/user/project/lib.h
#ifndef LIB_H
#define LIB_H
int process();
#endif
EOF

cat << 'EOF' > /home/user/project/lib.c
#include "lib.h"
#include <stdlib.h>

extern int get_magic();

int process() {
    int *arr = malloc(10 * sizeof(int));
    int sum = 0;

    // Fill array
    for(int i = 0; i < 10; i++) {
        arr[i] = get_magic();
    }

    // UB: out of bounds read
    for(int i = 0; i <= 10; i++) {
        sum += arr[i];
    }

    free(arr);
    return sum;
}
EOF

cat << 'EOF' > /home/user/project/main.go
package main

/*
#cgo CFLAGS: -I../src
#cgo LDFLAGS: -L../lib -lmyc
#include "lib.h"
*/
import "C"
import (
    "fmt"
    "os"
    "sync"
)

func main() {
    // TODO: Run C.process() in 15 goroutines, sum the results, and write to output.txt
}
EOF

cat << 'EOF' > /home/user/project/Makefile
all:
	gcc -shared -o libmyc.so -fPIC lib.c
EOF

chown -R user:user /home/user/project
chmod -R 777 /home/user
