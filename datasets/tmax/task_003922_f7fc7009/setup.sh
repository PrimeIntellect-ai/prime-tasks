#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang build-essential
pip3 install pytest

mkdir -p /home/user/investigation
cd /home/user/investigation

cat << 'EOF' > auth.log
2024-05-10T10:01:00Z sshd: Accepted publickey for user
2024-05-10T10:05:00Z kernel: [MAL] payload=IwYdc3Bx
2024-05-10T10:02:00Z kernel: [MAL] payload=HRIjOy4t
2024-05-10T10:04:00Z sshd: Disconnected from user
2024-05-10T10:01:30Z kernel: [MAL] payload=ESchMCc2
2024-05-10T10:06:00Z kernel: [MAL] payload=Yw==
EOF

cat << 'EOF' > decode.h
#ifndef DECODE_H
#define DECODE_H

void xor_decode(char* data, int len, char key);

#endif
EOF

cat << 'EOF' > decode.c
#include "decode.h"

void x0r_decode(char* data, int len, char key) {
    for(int i = 0; i < len; i++) {
        data[i] ^= key;
    }
}
EOF

cat << 'EOF' > extractor.go
package main

/*
#cgo CFLAGS: -I.
#include "decode.h"
#include <stdlib.h>
*/
import "C"
import (
	"bufio"
	"encoding/base64"
	"fmt"
	"os"
	"sort"
	"strings"
	"unsafe"
)

type LogEntry struct {
	Timestamp string
	Payload   string
}

func main() {
	file, err := os.Open("auth.log")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var entries []LogEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "[MAL] payload=") {
			parts := strings.Split(line, " ")
			// parts[0] is timestamp, parts[len(parts)-1] is payload=...
			payloadStr := strings.TrimPrefix(parts[len(parts)-1], "payload=")
			entries = append(entries, LogEntry{
				Timestamp: parts[0],
				Payload:   payloadStr,
			})
		}
	}

	// BUG: Sorting alphabetically by payload length instead of timestamp
	sort.Slice(entries, func(i, j int) bool {
		return len(entries[i].Payload) < len(entries[j].Payload)
	})

	var combinedBase64 string
	for _, e := range entries {
		combinedBase64 += e.Payload
	}

	decodedBytes, err := base64.StdEncoding.DecodeString(combinedBase64)
	if err != nil {
		panic(err)
	}

	// CGO Decryption
	cBytes := C.CBytes(decodedBytes)
	defer C.free(cBytes)

	C.xor_decode((*C.char)(cBytes), C.int(len(decodedBytes)), C.char(0x42))

	finalBytes := C.GoBytes(cBytes, C.int(len(decodedBytes)))

	// Assertion-based validation: The decrypted payload must start with 'S' (Secret)
	if finalBytes[0] != 'S' {
		panic("Assertion failed: Decrypted payload does not match expected signature")
	}

	err = os.WriteFile("payload.bin", finalBytes, 0644)
	if err != nil {
		panic(err)
	}
	fmt.Println("Payload successfully written to payload.bin")
}
EOF

go mod init investigation
go mod tidy

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
