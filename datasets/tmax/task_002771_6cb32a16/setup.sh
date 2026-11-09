#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import os
import random

random.seed(42)

log_path = '/home/user/system_logs.dat'
template_path = '/home/user/report_template.txt'

# Generate the template
with open(template_path, 'w') as f:
    f.write("Log Analysis Report\n")
    f.write("-------------------\n")
    f.write("First Anomaly Detected At: {" + "{FIRST_ANOMALY_TIMESTAMP}" + "}\n")
    f.write("Total Errors Logged: {" + "{TOTAL_ERRORS}" + "}\n")
    f.write("Status: Requires investigation\n")

total_errors = 0
first_anomaly_ts = None

window = []

with open(log_path, 'wb') as f:
    for i in range(10000):
        ts = 1620000000 + (i * 10)

        # Determine if error
        is_error = False
        if 4500 <= i <= 4550:
            # High error rate burst
            if random.random() < 0.5:
                is_error = True
        else:
            # Normal error rate
            if random.random() < 0.05:
                is_error = True

        if is_error:
            total_errors += 1
            msg = "ERROR Connection failed."
        else:
            msg = "INFO System running normal."

        # Add window logic to find the ground truth first anomaly
        window.append(is_error)
        if len(window) > 100:
            window.pop(0)

        if sum(window) == 20 and first_anomaly_ts is None:
            first_anomaly_ts = ts

        # Corrupt the text slightly
        line = "[" + str(ts) + "] " + msg
        raw_bytes = bytearray(line.encode('ascii'))
        if random.random() < 0.2:
            raw_bytes.insert(random.randint(0, len(raw_bytes)), 0xFF)
        if random.random() < 0.2:
            raw_bytes.insert(random.randint(0, len(raw_bytes)), 0x01)

        raw_bytes.extend(b'\n')
        f.write(raw_bytes)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
