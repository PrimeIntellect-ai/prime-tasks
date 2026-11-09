#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y gcc g++ make patch golang zlib1g-dev

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/workspace/cpp_server
    mkdir -p /home/user/workspace/go_runner

    # Create and compile sig_gen
    cat << 'EOF' > /tmp/sig_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <zlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(len);
    if(len > 0) fread(buf, 1, len, f);
    fclose(f);
    uint32_t crc = crc32(0L, Z_NULL, 0);
    if(len > 0) crc = crc32(crc, buf, len);
    uint32_t res = crc ^ 0x1337BEEF;
    printf("%08X\n", res);
    free(buf);
    return 0;
}
EOF
    gcc -O2 -s -o /app/sig_gen /tmp/sig_gen.c -lz
    chmod +x /app/sig_gen
    rm /tmp/sig_gen.c

    # Create cpp_server/Makefile
    cat << 'EOF' > /home/user/workspace/cpp_server/Makefile
all:
	g++ -o server server.cpp
EOF

    # Create cpp_server/server.cpp
    cat << 'EOF' > /home/user/workspace/cpp_server/server.cpp
#include <iostream>
#include <string>
// Missing includes: <thread>, <mutex>, etc.

int main() {
    std::cout << "Server starting..." << std::endl;
    // TODO: implement socket server
    // TODO: implement base64 decode and patch logic
    return 0;
}
EOF

    # Create go_runner/main.go
    cat << 'EOF' > /home/user/workspace/go_runner/main.go
package main

import (
	"fmt"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		go func(id int) {
			wg.Add(1) // BUG: wg.Add is inside the goroutine, causing race conditions and premature exit
			defer wg.Done()
			// simulates TCP call
		}(i)
	}
	wg.Wait()
	fmt.Println("All done")
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
