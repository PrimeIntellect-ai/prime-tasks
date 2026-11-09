#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/etl_worker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    srand(12345);

    int ts = 1600000000;
    const char* cats[] = {"A", "B", "C"};
    const char* fmts[] = {"JSON", "CSV", "XML"};

    for (int i = 1; i <= n; i++) {
        int r = rand() % 100;
        int duplicate = (r < 15); // 15% chance of duplication
        int iters = duplicate ? 2 : 1;

        int cat_idx = rand() % 3;
        int fmt_idx = rand() % 3;
        double val = (rand() % 1000) / 10.0;

        // Changepoint
        if (i > n * 0.7) {
            val *= 50.0;
        }

        for (int j = 0; j < iters; j++) {
            ts += (rand() % 10) + 1;
            printf("%d|%d|%s|", i, ts, fmts[fmt_idx]);
            if (strcmp(fmts[fmt_idx], "JSON") == 0) {
                printf("{\"id\":%d,\"category\":\"%s\",\"value\":%.2f}\n", i, cats[cat_idx], val);
            } else if (strcmp(fmts[fmt_idx], "CSV") == 0) {
                printf("%d,%s,%.2f\n", i, cats[cat_idx], val);
            } else {
                printf("<record><id>%d</id><category>%s</category><value>%.2f</value></record>\n", i, cats[cat_idx], val);
            }
        }
    }
    return 0;
}
EOF
    gcc -O2 /tmp/etl_worker.c -o /app/etl_worker
    strip /app/etl_worker
    chmod +x /app/etl_worker
    rm /tmp/etl_worker.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
