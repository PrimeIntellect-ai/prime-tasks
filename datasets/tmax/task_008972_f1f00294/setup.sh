#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create workspace directory
    mkdir -p /home/user/workspace

    # Create the buggy stats_buffer.py
    cat << 'EOF' > /home/user/workspace/stats_buffer.py
class SlidingWindowStats:
    def __init__(self, max_size):
        self.max_size = max_size
        self.buffer = []
        self.head = 0

    def add(self, value):
        if len(self.buffer) < self.max_size:
            self.buffer.append(value)
        else:
            # Bug 1: Off-by-one. Increments head before writing, skipping the true oldest element
            self.head = (self.head + 1) % self.max_size
            self.buffer[self.head] = value

    def get_percentile(self, p):
        if not self.buffer:
            return None
        sorted_buf = sorted(self.buffer)
        # Bug 2: Wrong formula for percentile index.
        # Correct: k = (len(sorted_buf) - 1) * (p / 100.0)
        k = len(sorted_buf) * (p / 100.0)
        f = int(k)
        c = k - f
        if f + 1 < len(sorted_buf):
            return sorted_buf[f] * (1.0 - c) + sorted_buf[f + 1] * c
        else:
            return sorted_buf[-1]
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
