#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific packages
    apt-get install -y gcc gcc-aarch64-linux-gnu libc6-dev-arm64-cross golang-go file

    # Create directories
    mkdir -p /home/user/project/c /home/user/project/go /home/user/project/lib/amd64 /home/user/project/lib/arm64 /home/user/project/bin

    # Create C header
    cat << 'EOF' > /home/user/project/c/fasthash.h
#ifndef FASTHASH_H
#define FASTHASH_H

char* fast_hash(const char* input);

#endif
EOF

    # Create C source with bug
    cat << 'EOF' > /home/user/project/c/fasthash.c
#include <stdlib.h>
#include <string.h>
#include "fasthash.h"

char* fast_hash(const char* input) {
    int len = strlen(input);
    // BUG: Allocating only len+1 bytes, but appending "HASH" requires len+5
    char* out = (char*)malloc(len + 1);
    if (!out) return NULL;

    for(int i = 0; i < len; i++) {
        out[i] = input[len - 1 - i];
    }
    out[len] = '\0';

    // Undefined behavior / buffer overflow occurs here
    strcat(out, "HASH");

    return out;
}
EOF

    # Create Go main
    cat << 'EOF' > /home/user/project/go/main.go
package main

/*
#include "../c/fasthash.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"os"
	"unsafe"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Missing argument")
		return
	}
	input := C.CString(os.Args[1])
	defer C.free(unsafe.Pointer(input))

	res := C.fast_hash(input)
	if res != nil {
		defer C.free(unsafe.Pointer(res))
		fmt.Println(C.GoString(res))
	}
}
EOF

    # Initialize Go module
    cd /home/user/project/go
    go mod init fasthash

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
