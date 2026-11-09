#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang gdb
    pip3 install pytest

    mkdir -p /app/cores /app/logs /app/.hidden

    # Create legacy hasher C source
    cat << 'EOF' > /tmp/legacy_hasher.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

int main() {
    char line[2048];
    while (fgets(line, sizeof(line), stdin)) {
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
            len--;
        }
        uint32_t hash = 0x811C9DC5;
        for (size_t i = 0; i < len; i++) {
            hash ^= (uint8_t)line[i];
            hash *= 0x01000193;
        }
        hash ^= (uint32_t)len;

        if (strstr(line, "CRASH") != NULL) {
            int *p = NULL;
            *p = 42; // crash
        }

        printf("%08x\n", hash);
    }
    return 0;
}
EOF

    # Compile and strip legacy hasher
    gcc -O2 /tmp/legacy_hasher.c -o /app/legacy_hasher
    strip /app/legacy_hasher

    # Create reference hasher Go source
    cat << 'EOF' > /tmp/reference_hasher.go
package main

import (
	"bufio"
	"fmt"
	"os"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Bytes()
		hash := uint32(0x811C9DC5)
		for _, b := range line {
			hash ^= uint32(b)
			hash *= 0x01000193
		}
		hash ^= uint32(len(line))
		fmt.Printf("%08x\n", hash)
	}
}
EOF

    # Compile reference hasher
    go build -o /app/.hidden/reference_hasher /tmp/reference_hasher.go

    # Generate core dump using gdb
    echo "CRASH" > /tmp/crash_input
    gdb -batch -ex "run < /tmp/crash_input" -ex "generate-core-file /app/cores/core.legacy_hasher.12345" /app/legacy_hasher || true

    # Fallback in case gdb fails to generate core dump due to build environment restrictions
    if [ ! -f /app/cores/core.legacy_hasher.12345 ]; then
        touch /app/cores/core.legacy_hasher.12345
    fi

    # Create container log
    cat << 'EOF' > /app/logs/container.log
2023-10-01T12:00:00Z INFO Processing input batch 492
2023-10-01T12:00:01Z DEBUG Input: hello world
2023-10-01T12:00:01Z DEBUG Input: test string
2023-10-01T12:00:02Z DEBUG Input: CRASH
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
