#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace
    mkdir -p /home/user/.local/share/Trash/files/

    cat << 'EOF' > /home/user/workspace/data_processor.py
def get_unique_elements(data):
    unique = []
    for item in data:
        if item not in unique:
            unique.append(item)
    return unique
EOF

    cat << 'EOF' > /home/user/.local/share/Trash/files/test_perf.py
import time
import sys
import os

# Ensure we can import data_processor
sys.path.append('/home/user/workspace')
from data_processor import get_unique_elements

def test_performance():
    data = list(range(50000)) + list(range(10000))
    start = time.time()
    res = get_unique_elements(data)
    duration = time.time() - start

    assert len(res) == 50000, f"Expected 50000 unique elements, got {len(res)}"

    if duration > 1.0:
        print(f"FAIL: Too slow ({duration:.2f}s). Expected under 1.0s.")
        sys.exit(1)
    else:
        with open("/home/user/workspace/success.log", "w") as f:
            f.write("PASS")
        print(f"PASS: Completed in {duration:.4f}s")

if __name__ == "__main__":
    test_performance()
EOF

    chmod -R 777 /home/user
