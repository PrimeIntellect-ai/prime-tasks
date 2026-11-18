#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest flask fastapi uvicorn pandas scikit-learn scipy python-multipart requests

    mkdir -p /app
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    int f1, f2, f3, f4, f5;
    while (fscanf(f, "%d,%d,%d,%d,%d", &f1, &f2, &f3, &f4, &f5) == 5) {
        float score = (f1 * 0.5) + (f2 * 2.0) - (f3 * 1.5) + (f4 * 0.1) - (f5 * 0.8);
        printf("%f\n", score);
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -o /app/prop_scorer
    strip /app/prop_scorer
    chmod +x /app/prop_scorer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
