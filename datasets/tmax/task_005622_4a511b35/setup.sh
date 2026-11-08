#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/system /home/user/data /home/user/output

    cat << 'EOF' > /home/user/logs/service_alpha.log
[03:00:01] INFO - Dispatched event_1
[03:00:02] INFO - Dispatched event_2
[03:00:03] INFO - Dispatched event_3
[03:00:04] INFO - Dispatched event_4
EOF

    cat << 'EOF' > /home/user/logs/service_beta.log
[03:00:01] INFO - Received event_1
[03:00:01] INFO - Processed event_1 successfully
[03:00:02] INFO - Received event_2
[03:00:02] ERROR - Exception processing event_2: UnicodeDecodeError
[03:00:03] INFO - Received event_3
[03:00:03] ERROR - Exception processing event_3: ZeroDivisionError
[03:00:04] INFO - Received event_4
[03:00:04] INFO - Processed event_4 successfully
EOF

    cat << 'EOF' > /tmp/generate_data.py
import json
import base64

def make_b64(d, encoding='utf-8'):
    return base64.b64encode(json.dumps(d).encode(encoding)).decode('ascii')

events = [
    {"event_id": "event_1", "payload": make_b64({"p1": {"x": 0, "y": 0}, "p2": {"x": 3, "y": 4}, "time_delta": 10}, 'utf-8')},
    {"event_id": "event_2", "payload": make_b64({"p1": {"x": 1, "y": 1}, "p2": {"x": 7, "y": 9}, "time_delta": 5}, 'utf-16le')},
    {"event_id": "event_3", "payload": make_b64({"p1": {"x": 5, "y": 5}, "p2": {"x": 5, "y": 5}, "time_delta": 0}, 'utf-8')},
    {"event_id": "event_4", "payload": make_b64({"p1": {"x": 10, "y": 10}, "p2": {"x": 20, "y": 10}, "time_delta": 2}, 'utf-8')}
]

with open('/home/user/data/raw_events.jsonl', 'w') as f:
    for e in events:
        f.write(json.dumps(e) + '\n')
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    cat << 'EOF' > /home/user/system/processor.py
import json
import math
import base64
import sys

def decode_payload(b64_str):
    raw = base64.b64decode(b64_str)
    return json.loads(raw.decode('utf-8')) # BUG: Fails on utf-16le

def compute_score(p1, p2, time_delta):
    # BUG 1: Missing sqrt for Euclidean distance
    dist = (p1['x'] - p2['x'])**2 + (p1['y'] - p2['y'])**2
    # BUG 2: Wrong formula and divides by time_delta (causes ZeroDivisionError)
    decay = math.exp(-0.1) / time_delta 
    return dist * decay

def main():
    results = []
    with open('/home/user/data/raw_events.jsonl', 'r') as f:
        for line in f:
            record = json.loads(line)
            try:
                payload = decode_payload(record['payload'])
                score = compute_score(payload['p1'], payload['p2'], payload['time_delta'])
                results.append({"event_id": record['event_id'], "score": round(score, 4)})
            except Exception as e:
                print(f"Failed to process {record['event_id']}: {e}", file=sys.stderr)

    with open('/home/user/output/anomalies.json', 'w') as f:
        json.dump(results, f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
