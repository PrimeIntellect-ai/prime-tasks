#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

# 1. Create cpu_metrics.csv
times = pd.date_range("2023-10-01 10:00:00", "2023-10-01 10:05:00", freq="1min", tz="UTC")
cpu = [40.0, np.nan, 50.0, 60.0, np.nan, 80.0]
df_cpu = pd.DataFrame({"timestamp": times, "cpu_usage": cpu})
# Format as ISO 8601 string
df_cpu["timestamp"] = df_cpu["timestamp"].dt.strftime("%Y-%m-%dT%H:%M:%SZ")
df_cpu.to_csv("/home/user/cpu_metrics.csv", index=False)

# 2. Create app_logs.txt
logs = """[Oct 01 10:00:15] INFO - Request processed in 100ms
[Oct 01 10:00:45] INFO - Request processed in 200ms
[Oct 01 10:01:05] ERROR - Database connection timeout
[Oct 01 10:01:10] WARN - Slow response latency: 500ms
[Oct 01 10:02:05] INFO - Request processed in 50ms
[Oct 01 10:04:15] INFO - Background task finished
[Oct 01 10:05:00] INFO - High latency: 900ms detected
[Oct 01 10:05:59] INFO - Request processed in 100ms
"""
with open("/home/user/app_logs.txt", "w") as f:
    f.write(logs)
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
