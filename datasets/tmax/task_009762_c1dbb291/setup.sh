#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go build-essential
    pip3 install pytest

    mkdir -p /home/user/release/libemu
    mkdir -p /home/user/release/go-emu

    cat << 'EOF' > /home/user/release/libemu/emu.h
#ifndef EMU_H
#define EMU_H
int process_byte(int b);
#endif
EOF

    cat << 'EOF' > /home/user/release/libemu/emu.c
#include "emu.h"
int process_byte(int b) {
    return b ^ 0x2A; // Simple XOR emulator cipher
}
EOF

    cat << 'EOF' > /home/user/release/libemu/Makefile
CC=gcc
CFLAGS=-O2

libemu.a: emu.o
    ar rcs libemu.a emu.o

emu.o: emu.c
    $(CC) $(CFLAGS) -c emu.c -o emu.o
EOF

    cat << 'EOF' > /home/user/release/go-emu/main.go
package main

// #cgo CFLAGS: -I../libemu
// #cgo LDFLAGS: -L../libemu -lemu
// #include "emu.h"
import "C"
import (
	"encoding/hex"
	"fmt"
	"os"
	"strings"
)

const (
	STATE_INIT = iota
	STATE_READING
	STATE_ESCAPED
)

func main() {
	data, err := os.ReadFile("../payload.hex")
	if err != nil {
		panic(err)
	}

	bytes, err := hex.DecodeString(strings.TrimSpace(string(data)))
	if err != nil {
		panic(err)
	}

	state := STATE_INIT
	var output []string

	for _, b := range bytes {
		switch state {
		case STATE_INIT:
			if b == 0xAA {
				state = STATE_READING
			}
		case STATE_READING:
			if b == 0xFF {
				state = STATE_INIT
			} else if b == 0xEE {
				// BUG: Missing state transition to STATE_ESCAPED
				// state = STATE_ESCAPED (Agent must add this)
			} else {
				res := C.process_byte(C.int(b))
				output = append(output, fmt.Sprintf("%d", int(res)))
			}
		case STATE_ESCAPED:
			res := C.process_byte(C.int(b))
			output = append(output, fmt.Sprintf("%d", int(res)))
			state = STATE_READING
		}
	}

	fmt.Println(strings.Join(output, " "))
}
EOF

    cat << 'EOF' > /home/user/release/payload.hex
AA1020EEFF30FF
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
