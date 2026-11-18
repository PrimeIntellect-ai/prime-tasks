#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy_cleaner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_IDS 1000

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <file_x> <file_y>\n", argv[0]);
        return 1;
    }

    FILE *f1 = fopen(argv[1], "r");
    FILE *f2 = fopen(argv[2], "r");
    if (!f1 || !f2) return 1;

    int x_vals[MAX_IDS];
    int x_valid[MAX_IDS];
    memset(x_valid, 0, sizeof(x_valid));

    char line[256];
    // Skip header
    fgets(line, sizeof(line), f1);
    while (fgets(line, sizeof(line), f1)) {
        int id, val;
        if (sscanf(line, "%d,%d", &id, &val) == 2) {
            if (id >= 0 && id < MAX_IDS) {
                x_vals[id] = val;
                x_valid[id] = 1;
            }
        }
    }
    fclose(f1);

    int results[MAX_IDS];
    int res_valid[MAX_IDS];
    memset(res_valid, 0, sizeof(res_valid));

    // Skip header
    fgets(line, sizeof(line), f2);
    while (fgets(line, sizeof(line), f2)) {
        int id, val;
        if (sscanf(line, "%d,%d", &id, &val) == 2) {
            if (id >= 0 && id < MAX_IDS && x_valid[id]) {
                if (x_vals[id] >= 0 && val >= 0) {
                    results[id] = x_vals[id] * val;
                    res_valid[id] = 1;
                }
            }
        }
    }
    fclose(f2);

    printf("id,product\n");
    for (int i = MAX_IDS - 1; i >= 0; i--) {
        if (res_valid[i]) {
            printf("%d,%d\n", i, results[i]);
        }
    }

    return 0;
}
EOF

    gcc -O2 /tmp/legacy_cleaner.c -o /app/legacy_cleaner
    strip /app/legacy_cleaner
    chmod +x /app/legacy_cleaner
    rm /tmp/legacy_cleaner.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
