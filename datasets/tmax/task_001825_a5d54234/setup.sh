#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils libc6-dev
    pip3 install pytest grpcio grpcio-tools capstone

    # Create directories
    mkdir -p /app/bin /app/src
    mkdir -p /home/user/workspace/src
    mkdir -p /home/user/workspace/corpus/clean
    mkdir -p /home/user/workspace/corpus/evil

    # Create the asset compiler source
    cat << 'EOF' > /app/src/asset_compiler.c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz);
    if (!buf) return 1;
    fread(buf, 1, sz, f);
    fclose(f);

    // Mock analysis: crashes if it finds ud2 (0x0f 0x0b)
    if (memmem(buf, sz, "\x0f\x0b", 2)) {
        int *p = NULL;
        *p = 1; // Segmentation fault
    }

    free(buf);
    return 0;
}
EOF

    # Compile and strip the asset compiler
    gcc -s -o /app/bin/asset_compiler /app/src/asset_compiler.c

    # Create pipeline.proto
    cat << 'EOF' > /home/user/workspace/pipeline.proto
syntax = "proto3";
package build_pipeline;

service AssetValidator {
    rpc ValidateAsset (AssetRequest) returns (AssetResponse) {}
}

message AssetRequest {
    bytes content = 1;
}

message AssetResponse {
    bool is_valid = 1;
    string reason = 2;
}
EOF

    # Create assembly sources for the corpora
    cat << 'EOF' > /home/user/workspace/src/clean1.s
.global _start
_start:
    nop
    nop
    ret
EOF

    cat << 'EOF' > /home/user/workspace/src/clean2.s
.global _start
_start:
    mov %eax, %eax
    ret
EOF

    cat << 'EOF' > /home/user/workspace/src/evil1.s
.global _start
_start:
    nop
    ud2
    ret
EOF

    cat << 'EOF' > /home/user/workspace/src/evil2.s
.global _start
_start:
    ud2
    int3
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/workspace/Makefile
all: dirs
	gcc -nostdlib -c src/clean1.s -o clean1.o
	objcopy -O binary clean1.o corpus/clean/clean1.bin
	gcc -nostdlib -c src/clean2.s -o clean2.o
	objcopy -O binary clean2.o corpus/clean/clean2.bin
	gcc -nostdlib -c src/evil1.s -o evil1.o
	objcopy -O binary evil1.o corpus/evil/evil1.bin
	gcc -nostdlib -c src/evil2.s -o evil2.o
	objcopy -O binary evil2.o corpus/evil/evil2.bin
	rm -f *.o

dirs:
	mkdir -p corpus/clean corpus/evil
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
