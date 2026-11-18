#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc binutils
    pip3 install --default-timeout=100 pytest requests

    mkdir -p /app
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    int counts[256] = {0};
    int total = 0;
    unsigned char c;

    while (fread(&c, 1, 1, f) == 1) {
        counts[c]++;
        total++;
    }
    fclose(f);

    if (total == 0) {
        printf("0.0000\n");
        return 0;
    }

    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (counts[i] > 0) {
            double p = (double)counts[i] / total;
            entropy -= p * log2(p);
        }
    }

    printf("%.6f\n", entropy);
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -o /app/legacy_scorer -lm
    strip /app/legacy_scorer
    chmod +x /app/legacy_scorer
    rm /tmp/scorer.c

    head -c 100 /dev/urandom > /app/file_high_entropy.bin
    echo "aaaaabbbbbcccccddddd" > /app/file_low_entropy.txt
    echo "hello world" > /app/file_tiny.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
