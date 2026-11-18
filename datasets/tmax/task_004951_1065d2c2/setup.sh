#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    unsigned long hash = 5381;
    int c;
    char* str = argv[1];
    while ((c = *str++)) hash = ((hash << 5) + hash) + c;
    srand(hash);
    for(int i=0; i<16; i++) {
        float val = ((float)rand() / RAND_MAX) * 2.0f - 1.0f;
        printf("%f ", val);
    }
    printf("\n");
    return 0;
}
EOF
gcc -O2 /app/oracle.c -o /app/embedding_oracle
strip /app/embedding_oracle
rm /app/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
