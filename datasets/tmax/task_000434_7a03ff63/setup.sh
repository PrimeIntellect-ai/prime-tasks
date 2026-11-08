#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Write C code for telemetry_oracle
    cat << 'EOF' > /app/telemetry_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    long last_epoch = -1;
    while (fgets(line, sizeof(line), stdin)) {
        long epoch;
        char key[256];
        int value;
        char hash[256];
        if (sscanf(line, "%ld,%[^,],%d,%s", &epoch, key, &value, hash) == 4) {
            if (epoch < last_epoch) {
                return 1;
            }
            last_epoch = epoch;
            if (strlen(key) > 64) {
                abort();
            }
            if (value < 0 || value > 10000) {
                int *p = NULL; *p = 1;
            }
            if (strstr(key, "../") || strchr(key, '$')) {
                int *p = NULL; *p = 1;
            }
        }
    }
    return 0;
}
EOF

    gcc -O2 -s /app/telemetry_oracle.c -o /app/telemetry_oracle
    rm /app/telemetry_oracle.c

    # Generate corpora using Python
    python3 -c '
import os
clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

for i in range(5):
    with open(f"{clean_dir}/clean_{i}.csv", "w") as f:
        f.write("timestamp_raw,config_key,value_raw,hash\n")
        f.write("1622543217,sys.cache.size,100,abc\n")
        f.write("1622543220,sys.cache.size,,def\n")
        f.write("1622543230,sys.cache.size,200,ghi\n")

for i in range(5):
    with open(f"{evil_dir}/evil_{i}.csv", "w") as f:
        f.write("timestamp_raw,config_key,value_raw,hash\n")
        if i == 0:
            f.write("1622543217,sys.cache.size,10001,abc\n")
        elif i == 1:
            f.write("1622543217,sys.cache.size,-1,abc\n")
        elif i == 2:
            f.write("1622543217,sys.cache.size../,100,abc\n")
        elif i == 3:
            f.write("1622543217,$sys.cache.size,100,abc\n")
        else:
            f.write("1622543217,sys.cache.size,100000,abc\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
