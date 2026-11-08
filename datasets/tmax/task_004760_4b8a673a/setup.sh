#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libarchive-dev binutils
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create stripped binary for reverse engineering
    cat << 'EOF' > /tmp/cfg_verify.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if(!f) return 1;
    char buf[16];
    if (fread(buf, 1, 16, f) != 16) return 1;
    if(memcmp(buf, "CFG_TRACKER_V1\0\0", 16) == 0) {
        system("tar -xzf payload.tar.gz");
    }
    fclose(f);
    return 0;
}
EOF
    gcc /tmp/cfg_verify.c -o /app/cfg_verify
    strip /app/cfg_verify

    # Create dummy corpora files
    printf "CFG_TRACKER_V1\0\0" > /app/corpora/clean/clean_1.cfg

    printf "CFG_TRACKER_V1\0\0" > /app/corpora/evil/evil_absolute.cfg
    printf "CFG_TRACKER_V1\0\0" > /app/corpora/evil/evil_traversal.cfg
    printf "CFG_TRACKER_V1\0\0" > /app/corpora/evil/evil_symlink.cfg
    printf "CFG_TRACKER_V1\0\0" > /app/corpora/evil/evil_bomb.cfg
    printf "BAD_HEADER_V1!\0\0" > /app/corpora/evil/evil_header.cfg

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
