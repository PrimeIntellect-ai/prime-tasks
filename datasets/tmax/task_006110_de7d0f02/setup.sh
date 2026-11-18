#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user/logs/service_A', exist_ok=True)
os.makedirs('/home/user/logs/service_B', exist_ok=True)

# Generate valid logs for Service A
with open('/home/user/logs/service_A/log1.bin', 'wb') as f:
    for i in range(10, 20):
        f.write(struct.pack('<ii', i * 100, i))

# Generate logs for Service B with one corrupted record
with open('/home/user/logs/service_B/log1.bin', 'wb') as f:
    for i in range(5, 15):
        if i == 12:
            # Corrupted record: timestamp -2147483648
            f.write(struct.pack('<ii', -2147483648, 999))
        else:
            f.write(struct.pack('<ii', i * 105, i))

# Create the buggy log_merger.py
buggy_code = """import os
import struct
import json
import multiprocessing
import glob

def process_file(file_path, queue):
    with open(file_path, 'rb') as f:
        while True:
            chunk = f.read(8)
            if not chunk or len(chunk) < 8:
                break

            ts, val = struct.unpack('<ii', chunk)

            # Intermediate validation
            assert ts >= 0, f"Corrupted timestamp {ts} detected!"

            queue.put({
                'service': os.path.basename(os.path.dirname(file_path)),
                'timestamp': ts,
                'value': val
            })

    # If the process crashes before this, DONE is never sent
    queue.put("DONE")

def main():
    queue = multiprocessing.Queue()
    files = glob.glob('/home/user/logs/*/*.bin')
    processes = []

    for f in files:
        p = multiprocessing.Process(target=process_file, args=(f, queue))
        processes.append(p)
        p.start()

    results = []
    active_workers = len(files)

    while active_workers > 0:
        item = queue.get()
        if item == "DONE":
            active_workers -= 1
        else:
            results.append(item)

    for p in processes:
        p.join()

    results.sort(key=lambda x: x['timestamp'])

    with open('/home/user/merged_timeline.json', 'w') as f:
        json.dump(results, f, indent=2)

if __name__ == '__main__':
    main()
"""

with open('/home/user/log_merger.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
