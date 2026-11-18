#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential wget
    pip3 install pytest setuptools wheel setuptools_scm

    mkdir -p /app/vendored
    cd /app/vendored
    wget -q https://files.pythonhosted.org/packages/source/u/ujson/ujson-5.7.0.tar.gz
    tar -xzf ujson-5.7.0.tar.gz
    rm ujson-5.7.0.tar.gz

    # Introduce perturbations
    sed -i 's/<Python.h>/<Pythonn.h>/g' ujson-5.7.0/python/ujson.c
    sed -i 's/PyMODINIT_FUNC/PyMODINIT_FUNCC/g' ujson-5.7.0/python/ujson.c

    useradd -m -s /bin/bash user || true

    # Generate raw logs
    python3 -c '
import json
with open("/app/raw_logs.txt", "w") as f:
    for i in range(10000):
        f.write(json.dumps({"id": i, "level": "INFO", "message": "Diagnostic log entry", "payload": "x"*50}) + "\n")
'

    # Create log_collector.py
    cat << 'EOF' > /home/user/log_collector.py
import multiprocessing
import ujson
import os

def process_chunk(lines):
    for line in lines:
        try:
            parsed = ujson.loads(line)
            parsed['processed'] = True
            # Race condition: multiple processes appending without locks
            with open('/home/user/diagnostics.jsonl', 'a') as f:
                f.write(ujson.dumps(parsed) + '\n')
        except Exception:
            pass

def main():
    with open('/app/raw_logs.txt', 'r') as f:
        lines = f.readlines()

    chunk_size = 1000
    chunks = [lines[i:i + chunk_size] for i in range(0, len(lines), chunk_size)]

    pool = multiprocessing.Pool(processes=4)
    pool.map(process_chunk, chunks)
    pool.close()
    pool.join()

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
