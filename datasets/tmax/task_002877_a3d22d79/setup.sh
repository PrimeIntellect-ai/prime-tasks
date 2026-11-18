#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/experiment_logs

    cat << 'EOF' > /tmp/generate_logs.py
import os, random

os.makedirs('/home/user/experiment_logs', exist_ok=True)

random.seed(42)

def generate_log(model, run_id, mean_tps, std_tps):
    num_tokens = random.randint(20, 100)
    tokens = ["word"] * num_tokens
    output_text = " ".join(tokens)

    tps = random.gauss(mean_tps, std_tps)
    latency_ms = (num_tokens / tps) * 1000

    return f"[2023-10-24 10:00:00] INFO: Inference complete. Model: {model}, Input ID: {run_id}, Latency: {latency_ms:.2f}ms, Output: {output_text}\n"

with open('/home/user/experiment_logs/model_A.log', 'w') as f:
    for i in range(100):
        f.write(generate_log('A', i, 50, 5))

with open('/home/user/experiment_logs/model_B.log', 'w') as f:
    for i in range(100):
        f.write(generate_log('B', i, 55, 5))
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
