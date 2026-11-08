#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_data
    mkdir -p /home/user/organized_data

    cat << 'EOF' > /home/user/checker.c
#include <stdio.h>
#include <string.h>

int check_magic(const char* filepath) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return 0;
    char buf[5] = {0};
    fread(buf, 1, 4, f);
    fclose(f);
    return strcmp(buf, "WXYZ") == 0 ? 1 : 0;
}
EOF

    gcc -shared -o /home/user/libchecker.so -fPIC /home/user/checker.c
    rm /home/user/checker.c

    echo -n "WXYZaGVsbG8=" > /home/user/legacy_data/file1.txt
    echo -n "WXYZY2Fm6Q==" > /home/user/legacy_data/file2.txt
    echo -n "ABCDY2Fm6Q==" > /home/user/legacy_data/file3.txt
    echo -n "WXYZamFsYXBl8W8=" > /home/user/legacy_data/file4.txt

    chmod -R 777 /home/user
