#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make zstd tar coreutils
    pip3 install pytest

    mkdir -p /home/user/legacy_data/project_a
    mkdir -p /home/user/legacy_data/project_b
    mkdir -p /home/user/spool
    mkdir -p /home/user/bin

    # Generate some ISO-8859-1 text files padded to be large enough to require compression
    # Using seq to ensure compatibility with /bin/sh
    for i in $(seq 1 50); do
      head -c 200000 /dev/urandom | base64 > /home/user/legacy_data/project_a/file_$i.txt
      # Inject some ISO-8859-1 specific characters
      printf '\xE9\xE0\xE7\xF9\n' >> /home/user/legacy_data/project_a/file_$i.txt
    done

    # Create the vendored package directory
    mkdir -p /app/fast-archiver-1.0
    cat << 'EOF' > /app/fast-archiver-1.0/Makefile
CC=gccc
CFLAGS=-Wall
LDFLAGS=

fast-archiver: main.c
	$(CC) $(CFLAGS) -o fast-archiver main.c $(LDFLAGS)
EOF

    # Create a mock main.c for fast-archiver (simulates zstd compression)
    cat << 'EOF' > /app/fast-archiver-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
/* Mock implementation: In a real environment, this would call zstd library functions. */
int main(int argc, char** argv) {
    if(argc < 3) return 1;
    char cmd[512];
    /* If compiled with -O3, use high compression, else use fast/low compression */
    #ifdef __OPTIMIZE__
        snprintf(cmd, sizeof(cmd), "tar -cf - %s | zstd -19 -o %s", argv[1], argv[2]);
    #else
        snprintf(cmd, sizeof(cmd), "tar -cf - %s | zstd -1 -o %s", argv[1], argv[2]);
    #endif
    system(cmd);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
