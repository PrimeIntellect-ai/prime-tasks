#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/oncall
    cd /home/user/oncall

    cat << 'EOF' > generate_logs.py
import json
import random

random.seed(42)
frontend_logs = []
backend_logs = []

for i in range(100):
    req_id = f"req_{i:04d}"
    ts_front = 1600000000 + i * 5
    ts_back = ts_front + random.randint(1, 3)
    proc_time = random.randint(150, 185) # Max is 185, average ~167

    frontend_logs.append({"ts": ts_front, "req_id": req_id, "endpoint": "/pay"})
    backend_logs.append({"ts": ts_back, "req_id": req_id, "proc_time_ms": proc_time})

# Shuffle logs to simulate async arrival
random.shuffle(frontend_logs)
random.shuffle(backend_logs)

with open("frontend.log", "w") as f:
    for log in frontend_logs:
        f.write(json.dumps(log) + "\n")

with open("backend.log", "w") as f:
    for log in backend_logs:
        f.write(json.dumps(log) + "\n")
EOF

    python3 generate_logs.py
    rm generate_logs.py

    cat << 'EOF' > aggregator.py
import sys
import json

def main():
    if len(sys.argv) != 3:
        print("Usage: python aggregator.py <frontend.log> <backend.log>")
        sys.exit(1)

    frontend_file = sys.argv[1]
    backend_file = sys.argv[2]

    # 1. Read logs
    requests = {}
    with open(frontend_file, 'r') as f:
        for line in f:
            record = json.loads(line)
            requests[record['req_id']] = record

    with open(backend_file, 'r') as f:
        for line in f:
            record = json.loads(line)
            req_id = record['req_id']
            if req_id in requests:
                requests[req_id]['proc_time_ms'] = record['proc_time_ms']

    # 2. Sort by frontend timestamp to reconstruct timeline
    merged_data = list(requests.values())
    merged_data.sort(key=lambda x: x['ts'])

    # 3. Compute 10-request rolling average
    window_size = 10
    for i in range(len(merged_data)):
        # BUG: Off-by-one window slice. Takes window_size + 1 elements.
        start_idx = max(0, i - window_size)
        window = merged_data[start_idx : i + 1]

        # BUG: Dividing by fixed window_size even at the boundary or with inflated window
        avg = sum(req['proc_time_ms'] for req in window) / window_size

        merged_data[i]['rolling_avg'] = avg
        if avg > 200:
            print(f"ANOMALY DETECTED: req_id={merged_data[i]['req_id']} avg={avg:.2f}", file=sys.stderr)

    # Output JSONL
    for req in merged_data:
        print(json.dumps(req))

if __name__ == "__main__":
    main()
EOF

    chmod +x aggregator.py
    chmod -R 777 /home/user
