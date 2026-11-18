#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/ts_ingester.c
#define _XOPEN_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        int commas = 0;
        for (int i=0; line[i]; i++) {
            if (line[i] == ',') commas++;
            if (line[i] == '\n' && commas < 3) {
                char *p = NULL;
                *p = 1; // trigger segfault
            }
        }
        char ts[256];
        int i=0;
        while(line[i] && line[i] != ',' && i < 255) {
            ts[i] = line[i];
            i++;
        }
        ts[i] = '\0';
        struct tm tm;
        memset(&tm, 0, sizeof(tm));
        char *ret1 = strptime(ts, "%Y-%m-%d %H:%M:%S", &tm);
        char *ret2 = strptime(ts, "%Y-%m-%dT%H:%M:%SZ", &tm);
        if ((ret1 == NULL || *ret1 != '\0') && (ret2 == NULL || *ret2 != '\0')) {
            printf("Parse error\n");
            return 1;
        }
    }
    fclose(f);
    return 0;
}
EOF
    gcc -s -o /app/ts_ingester /app/ts_ingester.c
    rm /app/ts_ingester.c

    cat << 'EOF' > /app/generate_corpus.py
import os
import random

clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

for i in range(20):
    with open(os.path.join(clean_dir, f"clean_{i}.csv"), "w") as f:
        fmt = random.choice(["%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ"])
        ts = "2023-10-25 14:22:10" if fmt == "%Y-%m-%d %H:%M:%S" else "2023-10-25T14:22:10Z"
        f.write(f"{ts},sensor{i},42.0,normal\n")

for i in range(10):
    with open(os.path.join(evil_dir, f"evil_nl_{i}.csv"), "w") as f:
        f.write(f"2023-10-25 14:22:10,sensor{i},42.0,\"error\nreboot\"\n")

for i in range(10):
    with open(os.path.join(evil_dir, f"evil_ts_{i}.csv"), "w") as f:
        f.write(f"2023/10/25 14:22:10,sensor{i},42.0,normal\n")
EOF
    python3 /app/generate_corpus.py
    rm /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
