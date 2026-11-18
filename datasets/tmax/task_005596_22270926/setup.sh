#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import base64
import struct

# Generate stream.txt
with open('/home/user/stream.txt', 'w') as f:
    for i in range(120):
        # Insert a value that triggers the precision/recursion bug at index 50
        if i == 50:
            val = 2.0
        else:
            val = 0.5 + (i % 10) * 0.1

        b = struct.pack('>d', val)
        f.write(base64.b64encode(b).decode() + '\n')

# Generate stat_service.py
code = """import sys
import base64
import struct

window_size = 10
recent_data = []
all_history = []  # Memory leak source

def decode_data(b64_str):
    b = base64.b64decode(b64_str)
    return struct.unpack('>d', b)[0]

def calculate_anomaly(val, score=0):
    # BUG: Float precision loss means val will miss exactly 0.0 (e.g. 2.0 - 0.1 - 0.1 ...)
    if val == 0.0:
        return score
    if score > 50:
        raise RecursionError("Anomaly calculation diverged due to precision loss!")
    return calculate_anomaly(val - 0.1, score + 1)

def process_stream(file_path):
    global all_history, recent_data
    with open(file_path, 'r') as f:
        for line in f:
            val = decode_data(line.strip())

            # Anomaly triggered for whole numbers > 0
            if val.is_integer() and val > 0:
                score = calculate_anomaly(val)
            else:
                score = val

            recent_data.append(score)
            all_history.append(score) # BUG: unbounded growth

            if len(recent_data) > window_size:
                recent_data.pop(0)

            if len(all_history) > 100:
                raise MemoryError("Memory limit exceeded - service leaked!")

if __name__ == "__main__":
    process_stream('/home/user/stream.txt')
    print(f"Processing complete. Final window average: {sum(recent_data)/len(recent_data):.4f}")
"""

with open('/home/user/stat_service.py', 'w') as f:
    f.write(code)

os.chmod('/home/user/stat_service.py', 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
