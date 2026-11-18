#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    mkdir -p /home/user/libs
    mkdir -p /home/user/data

    # 1. Create a dummy shared library (misconfiguration target)
    echo "int fast_add(int a, int b) { return a + b; }" > /tmp/fastmath.c
    gcc -shared -o /home/user/libs/libfastmath.so -fPIC /tmp/fastmath.c

    # 2. Create the SQLite DB and corrupt it slightly
    sqlite3 /home/user/sensor_data.db <<EOF
CREATE TABLE sensors (id INTEGER PRIMARY KEY, val1 REAL, val2 REAL, val3 REAL);
INSERT INTO sensors (val1, val2, val3) VALUES (100000000.0, 100000000.00001, 100000000.00002);
INSERT INTO sensors (val1, val2, val3) VALUES (100000000.00003, 100000000.00004, 100000000.00005);
INSERT INTO sensors (val1, val2, val3) VALUES (100000000.00006, 100000000.00007, 100000000.00008);
EOF
    # Corrupt the DB header so normal open fails, requiring .recover
    dd if=/dev/urandom of=/home/user/sensor_data.db bs=16 count=1 conv=notrunc

    # 3. Create math_utils.py
    cat << 'EOF' > /home/user/math_utils.py
def calc_variance(data):
    if not data: return 0.0
    n = len(data)
    mean = sum(data) / n
    # Naive, numerically unstable variance
    mean_sq = sum(x**2 for x in data) / n
    return mean_sq - mean**2
EOF

    # 4. Create service.py with a memory leak and missing env var dependence
    cat << 'EOF' > /home/user/service.py
import asyncio
import sqlite3
import json
import argparse
import ctypes
import os
from math_utils import calc_variance

# Fails if library not found
try:
    lib = ctypes.CDLL("libfastmath.so")
except OSError:
    raise RuntimeError("libfastmath.so not found! Environment misconfigured.")

active_tasks = set()

async def process_record(record):
    await asyncio.sleep(0.01) # Simulate async IO
    variance = calc_variance([record[1], record[2], record[3]])
    return {"id": record[0], "variance": variance}

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    cursor = conn.cursor()
    cursor.execute("SELECT id, val1, val2, val3 FROM sensors")
    records = cursor.fetchall()

    results = []
    for r in records:
        task = asyncio.create_task(process_record(r))
        active_tasks.add(task)
        # MEMORY LEAK: tasks are added to active_tasks to prevent GC, but never removed!

        res = await task
        results.append(res)

    with open(args.output, "w") as f:
        json.dump(results, f)

if __name__ == "__main__":
    asyncio.run(main())
EOF
    chmod +x /home/user/service.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
