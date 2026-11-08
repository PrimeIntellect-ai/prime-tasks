#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc redis-server
pip3 install pytest fastapi uvicorn redis maturin requests

mkdir -p /app/utils /app/rust_ecc/src

cat << 'EOF' > /app/api.py
from fastapi import FastAPI
import redis
import json

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

@app.post("/process")
async def process(data: list):
    r.lpush('queue', json.dumps(data))
    return {"status": "queued"}
EOF

cat << 'EOF' > /app/worker.py
import redis
import json
import time
from utils.naive_checksum import compute_checksum

r = redis.Redis(host='localhost', port=6379, db=0)

def main():
    while True:
        item = r.rpop('queue')
        if item:
            data = json.loads(item)
            res = compute_checksum(data)
            r.incr('processed_count')
        else:
            time.sleep(0.01)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /app/utils/__init__.py
EOF

cat << 'EOF' > /app/utils/naive_checksum.py
def compute_checksum(data):
    res = 0
    for _ in range(100):
        for x in data:
            res += x
    return res
EOF

cat << 'EOF' > /app/rust_ecc/Cargo.toml
[package]
name = "rust_ecc"
version = "0.1.0"
edition = "2021"

[lib]
name = "rust_ecc"
crate-type = ["cdylib"]

[dependencies]
pyo3 = "0.18.0"
EOF

cat << 'EOF' > /app/rust_ecc/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn compute_checksum(data: Vec<i64>) -> PyResult<i64> {
    let mut res = 0;
    for x in data {
        res += x;
    }
    let r1 = &mut res;
    let r2 = &mut res;
    *r1 += 1;
    *r2 += 1;
    Ok(res)
}

#[pymodule]
fn rust_ecc(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(compute_checksum, m)?)?;
    Ok(())
}
EOF

cat << 'EOF' > /app/benchmark.py
import requests
import time
import redis
import json
import argparse

def run_benchmark(json_output=None):
    r = redis.Redis(host='localhost', port=6379, db=0)
    r.set('processed_count', 0)
    r.delete('queue')

    start = time.time()
    for _ in range(1000):
        try:
            requests.post("http://localhost:8000/process", json=[1, 2, 3, 4, 5])
        except:
            pass

    while int(r.get('processed_count') or 0) < 1000:
        if time.time() - start > 10:
            break
        time.sleep(0.1)

    duration = time.time() - start
    count = int(r.get('processed_count') or 0)
    rps = count / duration if duration > 0 else 0

    res = {"requests_per_second": rps}
    print(f"Requests per second: {rps}")
    if json_output:
        with open(json_output, 'w') as f:
            json.dump(res, f)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output", type=str)
    args = parser.parse_args()
    run_benchmark(args.json_output)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
