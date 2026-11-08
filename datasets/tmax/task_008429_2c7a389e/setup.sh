#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go gcc libc6-dev coreutils
pip3 install pytest

mkdir -p /home/user/crypto-wrapper
cd /home/user/crypto-wrapper

cat << 'EOF' > crypto.h
#ifndef CRYPTO_H
#define CRYPTO_H
#include <stdint.h>
uint32_t calculate_crc32(const char *data);
void rot13_encode(const char *input, char *output);
#endif
EOF

cat << 'EOF' > crypto.c
#include "crypto.h"
#include <string.h>

uint32_t calculate_crc32(const char *data) {
    uint32_t crc = 0xFFFFFFFF;
    while (*data) {
        crc ^= (uint8_t)(*data++);
        for (int i = 0; i < 8; i++) {
            crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
        }
    }
    return ~crc;
}

void rot13_encode(const char *input, char *output) {
    while (*input) {
        char c = *input++;
        if (c >= 'a' && c <= 'm') c += 13;
        else if (c >= 'n' && c <= 'z') c -= 13;
        else if (c >= 'A' && c <= 'M') c += 13;
        else if (c >= 'N' && c <= 'Z') c -= 13;
        *output++ = c;
    }
    *output = '\0';
}
EOF

gcc -shared -o libcrypto.so -fPIC crypto.c

cat << 'EOF' > main.go
package main

/*
#cgo CFLAGS: -I.
#include "crypto.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"os"
	"unsafe"
)

type SecurePayload struct {
	Data     string
	Checksum uint32
}

func Process(input string) SecurePayload {
	cStr := C.CString(input)
	defer C.free(unsafe.Pointer(cStr))

	cOutput := (*C.char)(C.malloc(C.size_t(len(input) + 1)))
	defer C.free(unsafe.Pointer(cOutput))

	C.rot13_encode(cStr, cOutput)
	checksum := C.calculate_crc32(cOutput)

	return SecurePayload{
		Data:     C.GoString(cOutput),
		Checksum: uint32(checksum),
	}
}

func main() {
	if len(os.Args) < 2 {
		return
	}
	p := Process(os.Args[1])
	fmt.Printf("%s:%d\n", p.Data, p.Checksum)
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
