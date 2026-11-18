#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app/data
mkdir -p /home/user/app/logs

# Create data files
cat << 'EOF' > /home/user/app/data/data_1.json
{"sensor_1": 1.2, "sensor_2": -0.5}
EOF

cat << 'EOF' > /home/user/app/data/data_3.json
{"sensor_5": 0.0, "sensor_6": 10.0}
EOF

# Create UTF-16 encoded data file using python
python3 -c "open('/home/user/app/data/data_2.json', 'w', encoding='utf-16').write('{\"sensor_3\": 850.0, \"sensor_4\": -1200.0}')"

# Create log file
cat << 'EOF' > /home/user/app/logs/pipeline.log
[INFO] Starting pipeline
[INFO] Processing data_1.json
[INFO] Successfully processed data_1.json
[INFO] Processing data_2.json
[ERROR] Failed to read data_2.json: UnicodeDecodeError: 'utf-8' codec can't decode byte 0xff in position 0: invalid start byte
EOF

# Create processor.py script
cat << 'EOF' > /home/user/app/processor.py
import os
import glob
import json
import math

DATA_DIR = "/home/user/app/data"
OUTPUT_FILE = "/home/user/app/output.json"

def compute_activation(x):
    # Standard sigmoid function
    return 1.0 / (1.0 + math.exp(-x))

def process_files():
    results = {}
    files = glob.glob(os.path.join(DATA_DIR, "*.json"))

    for file_path in files:
        # BUG 1: Hardcoded UTF-8, fails on UTF-16 files
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        for key, value in data.items():
            # BUG 2: OverflowError when value is a large negative number (e.g. -1200)
            results[key] = compute_activation(value)

    with open(OUTPUT_FILE, 'w') as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    process_files()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
