#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils cargo rustc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/analyzer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fclose(f);
    printf("ANALYSIS_RESULT:%ld_OK\n", size);
    return 0;
}
EOF

    gcc /tmp/analyzer.c -o /app/build_analyzer
    strip /app/build_analyzer
    rm /tmp/analyzer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
