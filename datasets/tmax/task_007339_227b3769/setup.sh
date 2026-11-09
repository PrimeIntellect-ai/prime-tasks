#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/environment/src

    cat << 'EOF' > /home/user/environment/deps.txt
libD: libB libC
libB: libA
libC: libA
libA:
libE: libD
EOF

    cat << 'EOF' > /home/user/environment/checksum.c
#include <stdint.h>
#include <stdio.h>

int32_t custom_hash(const char* filepath) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return -1;
    int32_t hash = 0x12345678;
    int c;
    while ((c = fgetc(f)) != EOF) {
        hash ^= c;
        hash = (hash << 5) | ((hash >> 27) & 0x1F);
    }
    fclose(f);
    return hash;
}
EOF

    echo "void libA() {}" > /home/user/environment/src/libA.c
    echo "void libB() { libA(); }" > /home/user/environment/src/libB.c
    echo "void libC() { libA(); }" > /home/user/environment/src/libC.c
    echo "void libD() { libB(); libC(); }" > /home/user/environment/src/libD.c
    echo "void libE() { libD(); }" > /home/user/environment/src/libE.c

    chown -R user:user /home/user/environment
    chmod -R 777 /home/user
