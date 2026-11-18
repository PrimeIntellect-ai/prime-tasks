#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go build-essential
pip3 install pytest

mkdir -p /home/user/project

cat << 'EOF' > /home/user/project/asmgen.h
#ifndef ASMGEN_H
#define ASMGEN_H
void generate_asm(int id, const char* filename);
#endif
EOF

cat << 'EOF' > /home/user/project/asmgen.c
#include <stdio.h>
#include "asmgen.h"

void generate_asm(int id, const char* filename) {
    FILE *f = fopen(filename, "w");
    if (!f) return;
    fprintf(f, "PUSH %d\n", id);
    fprintf(f, "PUSH 10\n");
    fprintf(f, "MUL\n");
    fprintf(f, "PUSH 5\n");
    fprintf(f, "ADD\n");
    fprintf(f, "PRINT\n");
    fclose(f);
}
EOF

cat << 'EOF' > /home/user/project/main.go
package main

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L. -lasmgen
#include "asmgen.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"sync"
	"unsafe"
)

func main() {
	var wg sync.WaitGroup
	for i := 1; i <= 5; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			filename := C.CString(fmt.Sprintf("output_%d.asm", id))
			defer C.free(unsafe.Pointer(filename))
			C.generate_asm(C.int(id), filename)
		}(i)
	}
	wg.Wait()
}
EOF

cat << 'EOF' > /home/user/project/Makefile
all: generator

libasmgen.so: asmgen.c
	gcc -o libasmgen.so asmgen.c

generator: libasmgen.so main.go
	go build -o generator main.go

clean:
	rm -f generator libasmgen.so output_*.asm
EOF

cd /home/user/project
go mod init project || true

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
