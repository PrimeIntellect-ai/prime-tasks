#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /home/user/fast_process /home/user/server

    cat << 'EOF' > /home/user/fast_process/fast_hash.c
#include <string.h>

int compute_hash(const char* input) {
    if (!input || input[0] == '\0') return 0;
    int len = 0;
    while(input[len] != '\0') len++;
    return len * 100 + input[0];
}
EOF

    cat << 'EOF' > /home/user/fast_process/Makefile
all: libfasthash.so

libfasthash.so: fast_hash.c
	gcc -o libfasthash.so fast_hash.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
