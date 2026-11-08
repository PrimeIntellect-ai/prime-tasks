#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest requests flask fastapi uvicorn pandas

    mkdir -p /app

    cat << 'EOF' > /app/detect_outliers.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        double val = atof(line);
        if (fabs(val) > 15.0) {
            printf("1\n");
        } else {
            printf("0\n");
        }
        fflush(stdout);
    }
    return 0;
}
EOF

    gcc -O3 -s /app/detect_outliers.c -o /app/detect_outliers
    chmod +x /app/detect_outliers
    rm /app/detect_outliers.c

    cat << 'EOF' > /tmp/generate_db.py
import sqlite3

conn = sqlite3.connect('/tmp/test_data.sqlite')
c = conn.cursor()
c.execute("CREATE TABLE wide_readings (timestamp INTEGER, s1 REAL, s2 REAL, s3 REAL)")

for i in range(1, 101):
    s1 = i * 1.0
    s2 = i * 2.0
    s3 = i * 0.5

    if i == 50:
        s1 += 20.0
    if i == 75:
        s2 -= 30.0

    c.execute("INSERT INTO wide_readings VALUES (?, ?, ?, ?)", (i, s1, s2, s3))

conn.commit()
conn.close()
EOF

    python3 /tmp/generate_db.py
    rm /tmp/generate_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
