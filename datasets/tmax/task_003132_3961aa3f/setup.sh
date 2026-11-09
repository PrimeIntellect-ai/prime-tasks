#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/corpus/clean/art1 /app/corpus/clean/art2
    mkdir -p /app/corpus/evil/art1 /app/corpus/evil/art2 /app/corpus/evil/art3

    # Create clean 1
    mkdir -p /tmp/c1
    echo "hello world" > /tmp/c1/file.txt
    tar -czf /tmp/c1.tar.gz -C /tmp/c1 file.txt
    split -b 100 /tmp/c1.tar.gz /app/corpus/clean/art1/chunk_

    # Create clean 2
    mkdir -p /tmp/c2
    echo "another clean file" > /tmp/c2/file.txt
    tar -czf /tmp/c2.tar.gz -C /tmp/c2 file.txt
    split -b 100 /tmp/c2.tar.gz /app/corpus/clean/art2/chunk_

    # Create evil 1 (UTF-16LE payload)
    mkdir -p /tmp/e1
    echo -n "MALWARE_X99_PAYLOAD" | iconv -f UTF-8 -t UTF-16LE > /tmp/e1/payload.txt
    tar -czf /tmp/e1.tar.gz -C /tmp/e1 payload.txt
    split -b 100 /tmp/e1.tar.gz /app/corpus/evil/art1/chunk_

    # Create evil 2 (trailing garbage)
    cp /tmp/c1.tar.gz /tmp/e2.tar.gz
    echo "garbagebytes" >> /tmp/e2.tar.gz
    split -b 100 /tmp/e2.tar.gz /app/corpus/evil/art2/chunk_

    # Create evil 3 (corrupted gzip)
    head -c 50 /tmp/c1.tar.gz > /tmp/e3.tar.gz
    split -b 100 /tmp/e3.tar.gz /app/corpus/evil/art3/chunk_

    # Compile legacy scanner
    cat << 'EOF' > /tmp/scanner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1);
    fread(buf, 1, sz, f);
    fclose(f);
    buf[sz] = 0;
    if (strstr(buf, "MALWARE_X99_PAYLOAD")) return 1;
    return 0;
}
EOF
    gcc -o /app/legacy_scanner /tmp/scanner.c
    strip /app/legacy_scanner
    chmod +x /app/legacy_scanner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
