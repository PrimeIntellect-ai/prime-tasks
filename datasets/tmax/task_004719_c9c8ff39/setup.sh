#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        bc \
        gawk \
        binutils

    pip3 install pytest

    # Create oracle binary
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int c;
    int current = -1;
    int count = 0;
    while ((c = fgetc(stdin)) != EOF) {
        if (current == -1) {
            current = c;
            count = 1;
        } else if (c == current && count < 255) {
            count++;
        } else {
            fputc(current ^ 0x5A, stdout);
            fputc(count ^ 0x5A, stdout);
            current = c;
            count = 1;
        }
    }
    if (current != -1) {
        fputc(current ^ 0x5A, stdout);
        fputc(count ^ 0x5A, stdout);
    }
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_bin
    strip /app/oracle_bin
    rm /tmp/oracle.c

    # Create user and source files
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/encoder.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int c;
    int current = -1;
    int count = 0;
    char *buf = malloc(100); /* Memory leak, unused variable causes compilation error with -Werror */
    while ((c = fgetc(stdin)) != EOF) {
        if (current == -1) {
            current = c;
            count = 1;
        } else if (c == current && count < 255) {
            count++;
        } else {
            fputc(current ^ 0x5A, stdout);
            fputc(count ^ 0x5A, stdout);
            current = c;
            count = 1;
        }
    }
    if (current != -1) {
        fputc(current ^ 0x5A, stdout);
        fputc(count ^ 0x5A, stdout);
    }
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all: encoder

encoder: encoder.c
	gcc -O2 encoder.c -o encoder -Werror -Wall
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
