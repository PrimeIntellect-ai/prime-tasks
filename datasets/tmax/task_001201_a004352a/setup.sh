#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import struct
import base64

records = [
    (1, 100000000.1),
    (1, 100000000.2),
    (1, 100000000.3),
    (1, 100000000.4),
    (1, 100000000.5),
    (2, 500000000.1),
    (2, 500000000.5),
    (2, 500000000.9)
]

binary_data = b''
for sid, val in records:
    binary_data += struct.pack('<id', sid, val)

with open('/home/user/telemetry.b64', 'w') as f:
    f.write(base64.b64encode(binary_data).decode('ascii'))
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    cat << 'EOF' > /home/user/anomaly_detector.py
import base64
import struct
from collections import defaultdict

def calculate_variance(values):
    n = len(values)
    if n == 0:
        return 0.0
    # Naive variance calculation: E[X^2] - (E[X])^2
    # Prone to catastrophic cancellation for large values with small variances
    sum_sq = sum(x**2 for x in values)
    sum_val = sum(values)
    return (sum_sq / n) - ((sum_val / n) ** 2)

def main():
    with open('/home/user/telemetry.b64', 'r') as f:
        b64_data = f.read().strip()

    raw_bytes = base64.b64decode(b64_data)

    sensor_data = defaultdict(list)

    # BUG 1: Unpacking as '<if' (4-byte float) instead of '<id' (8-byte double)
    # This causes misalignment after the first record.
    record_size = struct.calcsize('<if') 

    for i in range(0, len(raw_bytes) - record_size + 1, record_size):
        chunk = raw_bytes[i:i+record_size]
        if len(chunk) == record_size:
            sensor_id, value = struct.unpack('<if', chunk)
            sensor_data[sensor_id].append(value)

    for sid, values in sensor_data.items():
        var = calculate_variance(values)
        print(f"Sensor {sid} variance: {var}")

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/anomaly_detector.py
    chmod -R 777 /home/user
