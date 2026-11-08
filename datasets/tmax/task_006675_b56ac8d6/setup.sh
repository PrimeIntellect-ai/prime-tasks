#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/log_processor.py
import sys
import json

# Global cache for failed requests (causes memory leak over long runs)
failed_requests = []

def process_file(filepath):
    total_val = 0
    with open(filepath, 'r') as f:
        for line in f:
            try:
                data = json.loads(line)
                total_val += data.get('val', 0)
            except json.JSONDecodeError:
                # Memory Leak: Unbounded caching of failed requests
                # Multiplied to simulate large object footprint in a short test
                failed_requests.append(line * 100000)
    return total_val

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python log_processor.py <file>")
        sys.exit(1)

    total = process_file(sys.argv[1])
    print(total)
EOF

    cat << 'EOF' > /tmp/gen.py
import random
random.seed(42)
corrupted_indices = {142, 888, 2045, 3333, 4999}
total = 0
with open("/home/user/requests.log", "w") as f:
    for i in range(1, 5001):
        if i in corrupted_indices:
            f.write(f'{"{"}"id": {i}, "val": {"}"}\n')
        else:
            val = random.randint(1, 100)
            total += val
            f.write(f'{"{"}"id": {i}, "val": {val}{"}"}\n')

with open("/tmp/expected_total", "w") as f:
    f.write(str(total))
EOF

    python3 /tmp/gen.py
    rm /tmp/gen.py

    chmod -R 777 /home/user
