#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app /verify/clean /verify/evil

    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    long ts, prev_ts = -1;
    float val;
    int first = 1;
    while (fscanf(f, "%ld,%f", &ts, &val) == 2) {
        if (val < -1.0 || val > 1.0) return 1;
        if (!first) {
            if (ts <= prev_ts) return 1;
            if (ts - prev_ts != 50) return 1;
        }
        prev_ts = ts;
        first = 0;
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/oracle.c -o /app/etl_oracle
    strip /app/etl_oracle
    rm /app/oracle.c

    python3 -c '
import os
os.makedirs("/verify/clean", exist_ok=True)
for i in range(5):
    with open(f"/verify/clean/clean_{i}.csv", "w") as f:
        ts = 1600000000 + i * 10000
        for j in range(10):
            f.write(f"{ts},{0.5}\n")
            ts += 50

os.makedirs("/verify/evil", exist_ok=True)
def write_evil(name, data):
    with open(f"/verify/evil/{name}.csv", "w") as f:
        for ts, val in data:
            f.write(f"{ts},{val}\n")

write_evil("evil_1", [(1000, 0.5), (1050, 0.5), (1050, 0.5)])
write_evil("evil_2", [(1000, 0.5), (1100, 0.5)])
write_evil("evil_3", [(1000, 0.5), (1050, 0.5), (1000, 0.5)])
write_evil("evil_4", [(1000, 1.5), (1050, 0.5)])
write_evil("evil_5", [(1000, -1.5), (1050, 0.5)])
write_evil("evil_6", [(1000, 0.5), (1049, 0.5)])
write_evil("evil_7", [(1000, 0.5), (1000, 0.5)])
write_evil("evil_8", [(1000, 0.5), (1050, 1.01)])
write_evil("evil_9", [(1000, 0.5), (1050, 0.5), (1150, 0.5)])
write_evil("evil_10", [(1000, 0.5), (1050, 0.5), (1040, 0.5)])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
