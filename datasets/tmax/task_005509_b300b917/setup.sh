#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/extract_record.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    // Fake mathematical operation to enforce standard library linking
    volatile double dummy = sin(1.5708);

    if(argc < 2) {
        fprintf(stderr, "Usage: %s <dump_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if(!f) {
        perror("Failed to open dump");
        return 1;
    }

    // The leaked payload is located at offset 0x3A in the dump
    fseek(f, 0x3A, SEEK_SET);
    char buf[64] = {0};
    fread(buf, 1, 40, f);

    printf("%s\n", buf);
    fclose(f);
    return 0;
}
EOF

    dd if=/dev/urandom of=/home/user/memory.dump bs=1 count=58 2>/dev/null
    echo -n "Q1JJVElDQUxfTEVBS19JTl9TRVNTSU9OX01BTkFHRVJfMHg4OEEx" >> /home/user/memory.dump
    dd if=/dev/urandom of=temp.junk bs=1 count=20 2>/dev/null
    cat temp.junk >> /home/user/memory.dump
    rm temp.junk

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
