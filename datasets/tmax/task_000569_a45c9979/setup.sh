#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat gcc g++ upx-ucl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    if (!fgets(line, sizeof(line), f)) return 1;
    line[strcspn(line, "\r\n")] = 0;
    if (strcmp(line, "featA,featB,featC") != 0) return 1;

    while (fgets(line, sizeof(line), f)) {
        int commas = 0;
        for(int i=0; line[i]; i++) {
            if(line[i] == ',') commas++;
        }
        if (commas != 2) return 1;
    }
    return 0;
}
EOF

    gcc -s -O2 -o /app/validator /tmp/validator.c
    upx /app/validator || true
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
