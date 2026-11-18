#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server e2fsprogs ext4magic
    pip3 install pytest fastapi uvicorn redis

    mkdir -p /app/data /app/worker/output /app/simulator /app/tests

    # Create simulator
    cat << 'EOF' > /app/simulator/main.py
import asyncio
import json
from fastapi import FastAPI
import redis.asyncio as redis
import random

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(generate_data())

async def generate_data():
    while True:
        # Generate tiny floats that cause precision issues when summed naively
        batch = [random.uniform(1e-10, 1e-9) for _ in range(100)]
        await r.lpush("sensor_data", json.dumps(batch))
        await asyncio.sleep(0.1)
EOF

    # Create worker
    cat << 'EOF' > /app/worker/aggregator.py
import json
import time
import redis
import os

def main():
    with open('/app/worker/config.json', 'r') as f:
        config = json.load(f)

    r = redis.Redis(host=config['redis_host'], port=config['redis_port'], db=0)

    os.makedirs('/app/worker/output', exist_ok=True)

    total = 0.0
    while True:
        item = r.brpop("sensor_data", timeout=1)
        if item:
            batch = json.loads(item[1])
            # Bug 1: Off-by-one
            for i in range(len(batch) + 1):
                # Bug 2: Naive float addition
                total += batch[i]

            with open('/app/worker/output/totals.csv', 'w') as f:
                f.write(f"total\n{total}\n")
        else:
            time.sleep(0.1)

if __name__ == "__main__":
    main()
EOF

    # Create start and stop scripts
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/simulator && uvicorn main:app --host 0.0.0.0 --port 8000 &
echo $! > /app/simulator.pid
cd /app/worker && python3 aggregator.py &
echo $! > /app/worker.pid
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/stop.sh
#!/bin/bash
kill $(cat /app/simulator.pid 2>/dev/null) 2>/dev/null || true
kill $(cat /app/worker.pid 2>/dev/null) 2>/dev/null || true
redis-cli shutdown 2>/dev/null || true
EOF
    chmod +x /app/stop.sh

    # Create partition image with deleted config.json
    mkdir -p /tmp/img_data
    cat << 'EOF' > /tmp/img_data/config.json
{"batch_size": 100, "redis_host": "localhost", "redis_port": 6379}
EOF
    # Create a 10MB ext4 image
    mke2fs -t ext4 -d /tmp/img_data /app/data/partition.img 10M
    # Delete the file to simulate accidental deletion
    debugfs -w -R "rm config.json" /app/data/partition.img
    rm -rf /tmp/img_data

    # Create evaluate_mse.py
    cat << 'EOF' > /app/tests/evaluate_mse.py
import pandas as pd
import math

def evaluate():
    try:
        df = pd.read_csv('/app/worker/output/totals.csv')
        # Dummy check for now, real evaluation will compare against a reference
        print("MSE evaluated")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    evaluate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
