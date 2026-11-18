#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import json
import os

np.random.seed(42)

# Nodes
nodes = ['N1', 'N2', 'N3', 'N4', 'N5']
datacenters = ['us-east', 'us-west', 'eu-central', 'us-east', 'us-west']
node_info = [{"node_id": n, "datacenter": d} for n, d in zip(nodes, datacenters)]

with open('/home/user/node_info.json', 'w') as f:
    json.dump(node_info, f)

# Logs
logs = []
log_id = 1

def add_logs(node, count, fail_rate, latency_mean, latency_std):
    global log_id
    for _ in range(count):
        status = 'fail' if np.random.rand() < fail_rate else 'success'
        latency = np.random.normal(latency_mean, latency_std)
        logs.append([log_id, node, max(10, latency), status])
        log_id += 1

add_logs('N1', 100, 0.05, 115.0, 10.0)
add_logs('N2', 5, 0.40, 110.0, 5.0)
add_logs('N3', 50, 0.02, 128.0, 8.0)
add_logs('N4', 80, 0.05, 118.0, 12.0)
add_logs('N5', 1, 0.00, 110.0, 2.0)

df = pd.DataFrame(logs, columns=['log_id', 'node_id', 'latency_ms', 'status'])
df.to_csv('/home/user/api_logs.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
