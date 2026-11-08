#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/raw
    mkdir -p /home/user/repo
    mkdir -p /app

    # Create mock files
    printf "\x7fELF some elf data" > /home/user/raw/approved_1.elf
    printf "; comment\nG1 X10 Y10\n" > /home/user/raw/approved_2.gcode
    printf "\x7fELF some other elf data" > /home/user/raw/rejected_1.elf
    printf "just some random text data" > /home/user/raw/approved_invalid.txt

    # Create WAL file
    cat << 'EOF' > /home/user/transactions.wal
[2023-10-01 10:00:00] APPROVE approved_1.elf
[2023-10-01 10:05:00] APPROVE rejected_1.elf
[2023-10-01 10:10:00] REJECT rejected_1.elf
[2023-10-01 10:15:00] APPROVE approved_2.gcode
[2023-10-01 10:20:00] APPROVE approved_invalid.txt
EOF

    # Create packer binary
    cat << 'EOF' > /tmp/packer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4 || strcmp(argv[1], "pack") != 0) {
        return 1;
    }
    FILE *in = fopen(argv[2], "rb");
    FILE *out = fopen(argv[3], "wb");
    if (!in || !out) return 1;

    fprintf(out, "PKGRV1");
    int c;
    while ((c = fgetc(in)) != EOF) {
        fputc(c ^ 0x42, out);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF
    gcc -O2 -s -o /app/packer /tmp/packer.c
    chmod +x /app/packer
    rm /tmp/packer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
