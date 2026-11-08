#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import struct
import random
import math

random.seed(42)

def generate_data():
    with open('/home/user/raw_sensors.bin', 'wb') as f:
        # 10 sensors
        sensors = {i: {'val': random.uniform(10, 50), 'drift': 0.0} for i in range(10)}
        sensors[3]['drift'] = 0.5  # Drifting sensor
        sensors[7]['drift'] = -0.3 # Drifting sensor

        for step in range(1000):
            for sid in range(10):
                sensors[sid]['val'] += sensors[sid]['drift'] + random.gauss(0, 1.0)
                val = sensors[sid]['val']
                ts = 1600000000 + step * 10 + sid

                # Corrupt 5% of records
                if random.random() < 0.05:
                    checksum = 9999999
                else:
                    checksum = sid ^ (ts & 0xFFFFFFFF)

                record = struct.pack('<IQfI', sid, ts, val, checksum)
                f.write(record)

if __name__ == '__main__':
    generate_data()
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
