#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > main.c
#include <stdio.h>
#include "utils.h"

// META: author:alice
// META: version:1.2

int main() {
    #ifndef SECRET_ID
    #error "SECRET_ID not defined"
    #endif
    printf("Secret: %d\n", SECRET_ID);
    print_utils();
    return 0;
}
EOF

    cat << 'EOF' > utils.c
#include <stdio.h>
#include "utils.h"

// META: module:utils
// META: status:stable

void print_utils() {
    printf("Utils loaded.\n");
}
EOF

    cat << 'EOF' > utils.h
#ifndef UTILS_H
#define UTILS_H
void print_utils();
#endif
EOF

    cat << 'EOF' > Makefile
app: main.o utils.o
    gcc -o app main.o utils.o

main.o: main.c
    gcc -c main.c

utils.o: utils.c
    gcc -c utils.c

clean:
    rm *.o app
EOF

    cat << 'EOF' > serialize_meta.py
import os
import glob

def serialize():
    files = sorted(glob.glob('*.c') + glob.glob('*.h'))
    with open('metadata.txt', 'w') as f:
        for fname in files:
            tags = []
            with open(fname, 'r') as cf:
                for line in cf:
                    if '// META:' in line:
                        parts = line.strip().split('// META:')[1].strip().split(':')
                        if len(parts) == 2:
                            tags.append((parts[0].strip(), parts[1].strip()))
            f.write(f"FILE: {fname}\n")
            f.write(f"TAGS: {len(tags)}\n")
            for k, v in tags:
                f.write(f"{k}={v}\n")

if __name__ == '__main__':
    serialize()
EOF
    chmod +x serialize_meta.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
