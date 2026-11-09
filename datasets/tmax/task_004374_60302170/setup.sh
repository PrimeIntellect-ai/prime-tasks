#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy

    mkdir -p /home/user

    python3 -c "
import json
import random
random.seed(42)
with open('/home/user/dataset.jsonl', 'w') as f:
    for i in range(1000):
        if i % 20 == 0:
            f.write(json.dumps({'id': i, 'text': None}) + '\n')
        else:
            f.write(json.dumps({'id': i, 'text': f'Sample text data {i}'}) + '\n')
"

    cat << 'EOF' > /home/user/benchmark.py
import json
import time
from scipy import stats
import numpy as np

def validate_record(record):
    if not isinstance(record.get('text'), str):
        raise ValueError("Invalid schema: text must be a string")
    return True

def load_data(filepath):
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            record = json.loads(line)
            try:
                validate_record(record)
                data.append(record)
            except ValueError:
                # BUG: Returns empty list instead of skipping the invalid record
                return []
    return data

def simulate_embedding(text):
    # simulate small inference delay
    time.sleep(0.0001)
    return [len(text), len(text)*2]

def main():
    dataset = load_data('/home/user/dataset.jsonl')

    times_A = []
    for d in dataset:
        start = time.perf_counter()
        simulate_embedding(d['text'])
        times_A.append(time.perf_counter() - start)

    times_B = []
    for d in dataset:
        start = time.perf_counter()
        time.sleep(0.00005) # Simulated faster batch inference
        times_B.append(time.perf_counter() - start)

    if not times_A or not times_B:
        with open('/home/user/benchmark_results.json', 'w') as f:
            json.dump({"error": "No data"}, f)
        return

    t_stat, p_val = stats.ttest_ind(times_A, times_B)

    with open('/home/user/benchmark_results.json', 'w') as f:
        json.dump({
            "valid_records_count": len(dataset),
            "p_value": p_val,
            "method_A_mean_time": float(np.mean(times_A)),
            "method_B_mean_time": float(np.mean(times_B))
        }, f)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
