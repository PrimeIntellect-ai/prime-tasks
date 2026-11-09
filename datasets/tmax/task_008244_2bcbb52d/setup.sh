#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    # Create the C source code
    cat << 'EOF' > reverser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char buffer[100000];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        int len = strlen(buffer);
        // Strip newline if present for clean reversing
        if (len > 0 && buffer[len-1] == '\n') {
            buffer[len-1] = '\0';
            len--;
        }
        for (int i = len - 1; i >= 0; i--) {
            putchar(buffer[i]);
        }
    }
    return 0;
}
EOF

    # Create a broken Makefile (spaces instead of tabs, wrong output name)
    cat << 'EOF' > Makefile
all: reverser.c
    gcc reverser.c -o wrong_name_binary
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
