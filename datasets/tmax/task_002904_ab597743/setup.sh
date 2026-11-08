#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential wget
    pip3 install pytest

    # Download and setup xxhash
    mkdir -p /app/vendored
    cd /app/vendored
    wget https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.2.tar.gz
    tar xzf v0.8.2.tar.gz
    mv xxHash-0.8.2 xxhash-0.8.2
    rm v0.8.2.tar.gz

    # Build oracle
    mkdir -p /app/oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "xxhash.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char* buf = malloc(size > 4 ? size : 4);
    memset(buf, 0, 4);
    if (size > 0) {
        size_t read_bytes = fread(buf, 1, size, f);
        (void)read_bytes;
    }
    fclose(f);

    XXH64_hash_t hash = XXH64(buf, size, 0);

    printf("%s %02x%02x%02x%02x %016llx\n", argv[1], buf[0], buf[1], buf[2], buf[3], (unsigned long long)hash);
    free(buf);
    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c /app/vendored/xxhash-0.8.2/xxhash.c -I/app/vendored/xxhash-0.8.2 -o /app/oracle/indexer_oracle
    strip /app/oracle/indexer_oracle
    rm /tmp/oracle.c

    # Perturb the Makefile
    sed -i 's/CC \?= gcc/CC = gcc-broken-compiler-99/g' /app/vendored/xxhash-0.8.2/Makefile

    # Create user and raw file paths
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_file_paths.txt
# Legacy paths
   /opt/data/file1.bin   
/opt/data/file2.bin

  # broken path
/var/lib/data.dat
EOF

    chmod -R 777 /home/user
