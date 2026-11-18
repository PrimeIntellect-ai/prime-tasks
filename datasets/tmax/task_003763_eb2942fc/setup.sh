#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    mkdir -p /home/user/math_project/src
    mkdir -p /home/user/math_project/include
    mkdir -p /home/user/math_project/lib

    cat << 'EOF' > /home/user/math_project/include/fib.h
#ifndef FIB_H
#define FIB_H
unsigned long long fib_mod(int n);
#endif
EOF

    cat << 'EOF' > /home/user/math_project/src/fib.c
#include "fib.h"

unsigned long long fib_mod(int n) {
    if (n == 0) return 0;
    unsigned long long a = 0, b = 1, c;
    for(int i = 2; i <= n; i++) {
        c = (a + b) % 1000000007;
        a = b;
        b = c;
    }
    return b;
}
EOF

    cat << 'EOF' > /home/user/math_project/Makefile
all:
        gcc -c src/fib.c -Iinclude -o src/fib.o
        gcc -o lib/libfib.so src/fib.o
EOF

    cat << 'EOF' > /home/user/math_project/main.go
package main

/*
#cgo CFLAGS: -I${SRCDIR}/wrong_include
#cgo LDFLAGS: -L${SRCDIR}/wrong_lib -lfib
#include "fib.h"
*/
import "C"
import (
    "fmt"
    "sync"
    "os"
)

func main() {
    inputs := []int{100000, 200000, 300000}
    var wg sync.WaitGroup
    ch := make(chan uint64, len(inputs))

    for _, n := range inputs {
        wg.Add(1)
        go func(val int) {
            defer wg.Done()
            res := C.fib_mod(C.int(val))
            ch <- uint64(res)
        }(n)
    }
    wg.Wait()
    close(ch)

    var sum uint64 = 0
    for v := range ch {
        sum = (sum + v) % 1000000007
    }

    err := os.WriteFile("/home/user/result.txt", []byte(fmt.Sprintf("%d\n", sum)), 0644)
    if err != nil {
        panic(err)
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
