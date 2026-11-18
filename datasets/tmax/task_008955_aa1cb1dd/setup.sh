#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import random

random.seed(42)
# Generate latencies with lambda = 0.05 (mean = 20)
latencies = [random.expovariate(0.05) for _ in range(1000)]

with open("/home/user/app_profile.log", "w") as f:
    for i, lat in enumerate(latencies):
        # Insert some noise
        if i % 7 == 0:
            f.write(f"[DEBUG] Cache miss for key {i*3}\n")
        if i % 13 == 0:
            f.write(f"[WARN] Connection timeout retry {i}\n")

        f.write(f"[INFO] Request ID: {i+1000} | Latency: {lat:.3f} ms\n")
'

    chmod -R 777 /home/user
