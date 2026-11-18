#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils gdb
    pip3 install pytest

    mkdir -p /app /opt/corpus/clean /opt/corpus/evil /home/user/samples

    # Create and compile legacy checker
    cat << 'EOF' > /app/legacy_checker.c
#include <stdio.h>
int main() {
    const char* r1 = "password=[A-Za-z0-9]{16}";
    const char* r2 = "AKIA[0-9A-Z]{16}";
    return 0;
}
EOF
    gcc -O2 -static /app/legacy_checker.c -o /app/legacy_checker
    strip /app/legacy_checker
    rm /app/legacy_checker.c
    chmod 755 /app/legacy_checker

    # Python script to generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import random
from datetime import datetime, timedelta

def generate_log(path, num_lines, anomaly=False, secret=False):
    start_time = datetime(2023, 10, 1, 0, 0, 0)
    lines = []

    if anomaly:
        anomaly_hour = start_time + timedelta(hours=random.randint(1, 100))
        for _ in range(52):
            ts = anomaly_hour + timedelta(minutes=random.randint(0, 59), seconds=random.randint(0, 59))
            lines.append(f"[{ts.strftime('%Y-%m-%d %H:%M:%S')}] SERVICE CONFIG=VAL")
        num_lines = max(0, num_lines - 52)

    # generate normal lines (spread out so no hour has > 50)
    # we just distribute them over 200 hours
    for i in range(num_lines):
        ts = start_time + timedelta(hours=i % 200, minutes=random.randint(0, 59))
        lines.append(f"[{ts.strftime('%Y-%m-%d %H:%M:%S')}] SERVICE CONFIG=VAL")

    if secret:
        ts = start_time + timedelta(hours=random.randint(0, 200))
        if random.choice([True, False]):
            secret_val = "password=" + "".join(random.choices("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", k=16))
        else:
            secret_val = "AKIA" + "".join(random.choices("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", k=16))
        lines.append(f"[{ts.strftime('%Y-%m-%d %H:%M:%S')}] SERVICE {secret_val}")

    lines.sort()

    with open(path, "w") as f:
        for line in lines:
            f.write(line + "\n")

random.seed(42)

for i in range(50):
    generate_log(f"/opt/corpus/clean/clean_{i}.log", 200)

for i in range(25):
    generate_log(f"/opt/corpus/evil/evil_anomaly_{i}.log", 200, anomaly=True)
for i in range(25, 50):
    generate_log(f"/opt/corpus/evil/evil_secret_{i}.log", 200, secret=True)

generate_log("/home/user/samples/sample_clean.log", 100)
generate_log("/home/user/samples/sample_anomaly.log", 100, anomaly=True)
generate_log("/home/user/samples/sample_secret.log", 100, secret=True)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    chmod -R 755 /opt/corpus

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
