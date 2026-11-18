#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /app
    cat << 'EOF' > /app/graph_builder
#!/usr/bin/env python3
import sys
import json

committed = 0
seen_srcs = set()
current_src = None

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) >= 4 and parts[0] == "ADD" and parts[1] == "EDGE":
        src = parts[2]
        if src != current_src:
            if src in seen_srcs:
                # Out of order / interleaved, drop to simulate deadlock prevention
                continue
            seen_srcs.add(src)
            current_src = src
        committed += 1

print(json.dumps({"committed_edges": committed}))
EOF
    chmod +x /app/graph_builder

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(42)
with open('/home/user/events.csv', 'w') as f:
    f.write("event_id,timestamp,src_node,dst_node,amount\n")
    for i in range(1, 1001):
        src = f"Node_{random.randint(1, 10)}"
        dst = f"Node_{random.randint(1, 10)}"
        amt = random.randint(10, 100)
        f.write(f"{i},{1600000000+i},{src},{dst},{amt}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
