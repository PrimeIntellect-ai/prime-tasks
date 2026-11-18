#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc parallel gawk sed
    pip3 install pytest pandas

    mkdir -p /data /app

    cat << 'EOF' > /app/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        int commas = 0;
        for (int i = 0; line[i]; i++) {
            if (line[i] == ',') commas++;
        }
        if (commas != 3) continue;

        char *ts = strtok(line, ",");
        char *sensor = strtok(NULL, ",");
        char *payload = strtok(NULL, ",");
        char *reading_str = strtok(NULL, ",");
        if (reading_str) {
            double reading = atof(reading_str);
            if (reading > 30.0) {
                printf("%s,%s\n", ts, sensor);
            }
        }
    }
    return 0;
}
EOF
    gcc -O3 /app/analyzer.c -o /app/analyzer
    strip /app/analyzer
    rm /app/analyzer.c

    cat << 'EOF' > /tmp/gen_data.py
import math
import random

with open('/data/telemetry.csv', 'w') as f, open('/data/ground_truth.csv', 'w') as gt:
    for i in range(500000):
        ts = f"2023-01-01T00:00:00Z_{i}"
        sensor = f"S{i%10}"
        is_anomaly = (i % 100 == 0)

        if is_anomaly:
            reading = 40.0 + random.random()
            gt.write(f"{ts},{sensor}\n")
            has_newline = (i % 200 == 0)
            if has_newline:
                payload = f'"Payload\n{i}"'
            else:
                payload = f'"Payload {i}"'
        else:
            reading = 10.0 + math.sin(i / 10.0)
            payload = f'"Payload {i}"'

        f.write(f"{ts},{sensor},{payload},{reading:.2f}\n")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
