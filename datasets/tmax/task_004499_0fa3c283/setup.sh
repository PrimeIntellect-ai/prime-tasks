#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip strace
pip3 install pytest

mkdir -p /home/user/uptime_pipeline/logs
mkdir -p /home/user/uptime_pipeline/data

# 1. Create the binary data file containing double precision (float64) values
python3 -c "
import struct
with open('/home/user/uptime_pipeline/data/raw_metrics.bin', 'wb') as f:
    f.write(struct.pack('5d', 99.9999, 99.9995, 99.9, 99.99999, 99.99))
"

# 2. Create the buggy Python script
cat << 'EOF' > /home/user/uptime_pipeline/process_metrics.py
import os
import struct
import csv

def read_config():
    # Silently tries to open a config file
    try:
        with open('/home/user/.sre_monitor_conf', 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return "DEFAULT"

def process_data():
    mode = read_config()
    if mode != "STRICT_MODE":
        print("Running in default mode (metrics disabled).")
        return

    with open('/home/user/uptime_pipeline/data/raw_metrics.bin', 'rb') as f:
        data = f.read()

    # BUG: Unpacking as 32-bit floats ('f') instead of 64-bit doubles ('d') causing precision loss
    try:
        # 5 floats = 20 bytes, but file is 40 bytes (5 doubles). 
        # To simulate the bug where they read it as floats, we slice or unpack wrong.
        # Actually, let's just make the bug 'f' instead of 'd' and handle the size mismatch.
        # Let's read 8 bytes at a time, but unpack the first 4 bytes as float.
        values = []
        for i in range(5):
            chunk = data[i*8:(i+1)*8]
            # BUGGY LINE:
            val = struct.unpack('f', chunk[:4])[0] 
            # val = struct.unpack('d', chunk)[0] # CORRECT LINE
            values.append(val)
    except Exception as e:
        print(f"Error: {e}")
        return

    with open('/home/user/uptime_pipeline/metrics_output.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['MetricID', 'Uptime'])
        for i, val in enumerate(values):
            writer.writerow([i, f"{val:.5f}"])

if __name__ == '__main__':
    process_data()
EOF

# 3. Create the log files
cat << 'EOF' > /home/user/uptime_pipeline/logs/api_gateway.log
1710000000 INFO Server started
1710000045 INFO Request received
1710000120 ERROR TIMEOUT connecting to DB
1710000125 INFO Retrying
EOF

cat << 'EOF' > /home/user/uptime_pipeline/logs/db_backend.log
1710000001 INFO DB started
1710000050 INFO Query executed
1710000118 ERROR TIMEOUT waiting for lock
1710000122 ERROR TIMEOUT waiting for lock
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
