#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 build-essential
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/recovery.sql
BEGIN TRANSACTION;
CREATE TABLE readings (id INTEGER PRIMARY KEY, value REAL);
INSERT INTO readings (value) VALUES (1000000.001);
INSERT INTO readings (value) VALUES (1000000.002);
INSERT INTO readings (value) VALUES (1000000.003);
INSERT INTO readings (value) VALUES (1000000.004);
INSERT INTO readings (value) VALUES (1000000.005);
CRASH INSRT NTO readings VALUES (1000000.006);
EOF

    cat << 'EOF' > /home/user/pipeline/variance.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    double val;
    double sum = 0.0;
    double sum_sq = 0.0;
    int count = 0;

    while (scanf("%lf", &val) == 1) {
        sum += val;
        sum_sq += (val * val);
        count++;
    }

    if (count < 2) {
        printf("0.000000\n");
        return 0;
    }

    // Naive sample variance: (E[X^2] - (E[X])^2 / N) / (N-1)
    // Vulnerable to catastrophic cancellation
    double variance = (sum_sq - (sum * sum) / count) / (count - 1);

    printf("%.6f\n", variance);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/Makefile
all:
	gcc variance.c -o variance --this-flag-does-not-exist
EOF

    cat << 'EOF' > /home/user/pipeline/verify.py
import sqlite3
import statistics
import os

if not os.path.exists('/home/user/pipeline/sensor.db'):
    exit(1)

conn = sqlite3.connect('/home/user/pipeline/sensor.db')
c = conn.cursor()
c.execute("SELECT value FROM readings")
rows = c.fetchall()
vals = [r[0] for r in rows]

if len(vals) < 2:
    exit(1)

expected_variance = statistics.variance(vals)
expected_str = f"{expected_variance:.6f}"

try:
    with open('/home/user/pipeline/final_result.txt', 'r') as f:
        actual_str = f.read().strip()
except Exception:
    exit(1)

if expected_str != actual_str:
    exit(1)

# also check if the script test_variance exists
if not (os.path.exists('/home/user/pipeline/test_variance.sh') or os.path.exists('/home/user/pipeline/test_variance.py')):
    exit(1)

exit(0)
EOF
    chmod +x /home/user/pipeline/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
