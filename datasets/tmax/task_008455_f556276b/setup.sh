#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/vuln_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int process_data(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return -1;

    int state_counter = 0;
    char *buf = malloc(32); // Uninitialized heap allocation
    fread(buf, 1, 16, f);

    for (int i = 0; i < 16; i++) {
        if (buf[i] == 'A') {
            state_counter++;
        }
        if (buf[i] == 'X') {
            // Suspicious logic: uses uninitialized memory past index 16
            if (buf[i + 16] == (char)0xFF) {
                // Trigger artificial crash
                char *crash = NULL;
                *crash = 1;
            }
        }
        state_counter += 2;
    }

    free(buf);
    fclose(f);
    return state_counter;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    process_data(argv[1]);
    return 0;
}
EOF

    python3 -c 'with open("/home/user/payload.bin", "wb") as f: f.write(b"AAA_X" + b"\x00"*11)'

    cd /home/user && gcc -g -o vuln_parser vuln_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
