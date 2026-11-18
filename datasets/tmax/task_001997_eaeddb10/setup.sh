#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/log_part1.csv
timestamp,tx_id,resource_id,action
1,T1,R1,ACQUIRE
2,T2,R2,ACQUIRE
3,T3,R3,ACQUIRE
4,T4,R4,ACQUIRE
5,T5,R5,ACQUIRE
6,T1,R2,REQUEST
7,T2,R3,REQUEST
8,T6,R6,ACQUIRE
EOF

    cat << 'EOF' > /home/user/data/log_part2.csv
timestamp,tx_id,resource_id,action
9,T3,R1,REQUEST
10,T5,R2,REQUEST
11,T4,R2,REQUEST
12,T5,R4,REQUEST
13,T6,R1,REQUEST
14,T6,R6,RELEASE
15,T7,R6,ACQUIRE
16,T8,R6,REQUEST
17,T9,R6,REQUEST
18,T8,R6,RELEASE
19,T7,R6,RELEASE
EOF

    cat << 'EOF' > /tmp/validate_deadlocks.py
import json

expected = {
  "deadlocks": [
    ["T1", "T2", "T3"]
  ],
  "bottleneck_tx": "T2",
  "bottleneck_centrality": 0.2381
}

with open('/home/user/deadlock_report.json', 'r') as f:
    actual = json.load(f)

assert actual['deadlocks'] == expected['deadlocks'], f"Expected deadlocks {expected['deadlocks']}, got {actual.get('deadlocks')}"
assert actual['bottleneck_tx'] == expected['bottleneck_tx'], f"Expected bottleneck_tx {expected['bottleneck_tx']}, got {actual.get('bottleneck_tx')}"
assert abs(actual['bottleneck_centrality'] - expected['bottleneck_centrality']) < 0.001, f"Expected centrality {expected['bottleneck_centrality']}, got {actual.get('bottleneck_centrality')}"

print("Success")
EOF

    chmod -R 777 /home/user
