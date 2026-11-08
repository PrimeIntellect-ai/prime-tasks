#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <string.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *text = argv[1];
    unsigned long hash = 5381;
    int c;
    while ((c = *text++)) { hash = ((hash << 5) + hash) + c; }
    float e0 = (float)(hash % 1000) / 1000.0f;
    float e1 = (float)((hash / 17) % 1000) / 1000.0f;
    float e2 = (float)((hash / 31) % 1000) / 1000.0f;
    float e3 = (float)((hash / 73) % 1000) / 1000.0f;
    printf("%.4f %.4f %.4f %.4f\n", e0, e1, e2, e3);
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -o /app/scorer_bin
    strip /app/scorer_bin
    chmod +x /app/scorer_bin
    rm /tmp/scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
