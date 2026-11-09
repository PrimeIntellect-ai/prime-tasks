#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the /app directory
    mkdir -p /app

    # Write the C source code
    cat << 'EOF' > /tmp/auth_cli.c
#include <stdio.h>

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    unsigned int hash = 5381;
    char *str = argv[1];
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    printf("%08x\n", hash);
    return 0;
}
EOF

    # Compile the C code into a stripped binary
    gcc -O2 -s /tmp/auth_cli.c -o /app/auth_cli
    chmod +x /app/auth_cli

    # Cleanup
    rm /tmp/auth_cli.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
