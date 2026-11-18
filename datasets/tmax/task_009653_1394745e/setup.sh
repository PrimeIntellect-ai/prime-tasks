#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

n = 1000
timestamps = pd.date_range("2023-01-01", periods=n, freq="T")

# CPU usage with some extreme outliers
cpu_usage = np.random.normal(50, 10, n)
cpu_usage[10] = 120 # Outlier
cpu_usage[50] = -10 # Outlier
cpu_usage[100] = 95 # Outlier (might be > mean + 3*std)

memory_usage = np.random.uniform(20, 80, n)

# Log messages
messages = [
    "Connection successful.",
    "Error: Timeout occurred while fetching data!",
    "System reboot initiated.",
    "User logged in.",
    "Database connection timeout.",
    "Disk space running low...",
    "All systems operational."
]
log_message = np.random.choice(messages, n)

# Latency
latency_ms = np.random.normal(100, 20, n)
# Make latency higher if "timeout" is in message
timeout_mask = np.array(["timeout" in msg.lower() for msg in log_message])
latency_ms[timeout_mask] += 50

# Add missing values
latency_ms[20:30] = np.nan
latency_ms[200] = np.nan

df = pd.DataFrame({
    "timestamp": timestamps,
    "cpu_usage": cpu_usage,
    "memory_usage": memory_usage,
    "latency_ms": latency_ms,
    "log_message": log_message
})

df.to_csv("/home/user/server_logs.csv", index=False)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
