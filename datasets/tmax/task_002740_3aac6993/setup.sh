#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app
cd /home/user/app

cat << 'EOF' > sensor_daemon.py
import json
import sys

class SensorProcessor:
    def __init__(self):
        self.emas = {}
        self.retry_queue = []
        self.alpha = 0.5

    def parse_hex(self, hex_str):
        # BUG: Parses as unsigned 8-bit, fails to handle signed 8-bit
        return int(hex_str, 16)

    def process_readings(self, filepath):
        with open(filepath, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) != 2:
                    continue
                sensor_id, hex_val = parts

                val = self.parse_hex(hex_val)

                # EMA update
                if sensor_id not in self.emas:
                    self.emas[sensor_id] = val
                else:
                    prev = self.emas[sensor_id]
                    new_ema = self.alpha * val + (1 - self.alpha) * prev

                    # Sanity check: if step is huge, assume convergence failure and retry later
                    if abs(new_ema - prev) > 50:
                        self.retry_queue.append({"id": sensor_id, "val": val, "prev": prev})
                        # Memory leak: keeps appending to retry_queue and never processes it
                    else:
                        self.emas[sensor_id] = new_ema

        print(json.dumps(self.emas))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python sensor_daemon.py <data_file>")
        sys.exit(1)
    processor = SensorProcessor()
    processor.process_readings(sys.argv[1])
EOF

cat << 'EOF' > test_data.txt
s1,00
s1,02
s1,01
s2,ff
s2,fe
s2,fd
s3,7f
s3,80
s3,81
EOF

cat << 'EOF' > service.log
INFO: Starting sensor daemon...
WARNING: EMA step too large for s2. Queued for retry.
WARNING: EMA step too large for s2. Queued for retry.
WARNING: EMA step too large for s3. Queued for retry.
ERROR: Memory usage exceeded 90%. Generating heap dump...
EOF

cat << 'EOF' > heap.dump
0x00A1B2C3: list object: [{"id": "s2", "val": 255, "prev": -1}, {"id": "s2", "val": 254, "prev": -1}, ...] (size: 450MB)
0x00A1B2C4: dict object: emas map (size: 2KB)
EOF

chmod +x sensor_daemon.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
