#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc libssl-dev
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/data
    mkdir -p /home/user/telemetry

    # Create C source for telemetry_decoder
    cat << 'EOF' > /tmp/telemetry_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <openssl/md5.h>

int main() {
    char buffer[1024];
    size_t len = fread(buffer, 1, sizeof(buffer), stdin);
    if (len > 512) {
        char *p = NULL;
        *p = 1; // Segfault
    }
    if (len >= 2 && (unsigned char)buffer[0] == 0xDE && (unsigned char)buffer[1] == 0xAD) {
        abort(); // SIGABRT
    }
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)buffer, len, digest);
    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        printf("%02x", digest[i]);
    }
    printf("\n");
    return 0;
}
EOF

    # Compile the C program and strip it
    gcc -O2 /tmp/telemetry_decoder.c -o /app/telemetry_decoder -lcrypto -Wno-deprecated-declarations
    strip /app/telemetry_decoder

    # Generate raw telemetry data
    cat << 'EOF' > /tmp/generate_data.py
import struct
import random

random.seed(42)

with open('/home/user/data/raw_telemetry.bin', 'wb') as f:
    for i in range(10000):
        if i < 500:
            length = random.randint(513, 800)
            payload = bytes([random.randint(0, 255) for _ in range(length)])
        elif i < 700:
            length = random.randint(2, 512)
            payload = b'\xDE\xAD' + bytes([random.randint(0, 255) for _ in range(length - 2)])
        else:
            length = random.randint(1, 512)
            payload = bytes([random.randint(0, 255) for _ in range(length)])
            if payload.startswith(b'\xDE\xAD'):
                payload = b'\x00\x00' + payload[2:]

        f.write(struct.pack('<I', i))
        f.write(struct.pack('<I', length))
        f.write(payload)
EOF
    python3 /tmp/generate_data.py

    # Create Go source file
    cat << 'EOF' > /home/user/telemetry/main.go
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strconv"
	"sync"
)

func main() {
	data, err := os.ReadFile("/home/user/data/raw_telemetry.bin")
	if err != nil {
		panic(err)
	}

	results := make(map[string]string)
	var wg sync.WaitGroup

	buf := bytes.NewReader(data)
	for {
		var id uint32
		var length uint32

		err := binary.Read(buf, binary.LittleEndian, &id)
		if err == io.EOF {
			break
		}
		binary.Read(buf, binary.LittleEndian, &length)

		payload := make([]byte, length)
		buf.Read(payload)

		wg.Add(1)
		go func(id uint32, payload []byte) {
			defer wg.Done()

			cmd := exec.Command("/app/telemetry_decoder")
			cmd.Stdin = bytes.NewReader(payload)
			out, err := cmd.Output()
			if err != nil {
				panic("Pipeline aborted due to decoder crash")
			}

			results[strconv.Itoa(int(id))] = string(bytes.TrimSpace(out))
		}(id, payload)
	}

	wg.Wait()

	outJson, _ := json.Marshal(results)
	os.WriteFile("/home/user/telemetry/output.json", outJson, 0644)
}
EOF

    cd /home/user/telemetry && go mod init telemetry

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
