#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    mkdir -p /home/user/pipeline/tests

    # Generate audio file
    espeak -w /app/spec_memo.wav "The quadratic coefficients are four, negative seven, and fifteen. The rate limit is exactly three requests per second."

    # Create mock whisper-cli
    cat << 'EOF' > /usr/local/bin/whisper-cli
#!/bin/bash
echo "The quadratic coefficients are four, negative seven, and fifteen. The rate limit is exactly three requests per second."
EOF
    chmod +x /usr/local/bin/whisper-cli

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
from collections import deque

def main():
    A, B, C = 4, -7, 15
    limit = 3
    window = 1000
    history = deque()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        ts, x = int(parts[0]), int(parts[1])

        while history and history[0] <= ts - window:
            history.popleft()

        if len(history) >= limit:
            print("REJECTED")
        else:
            history.append(ts)
            ans = A * (x**2) + B * x + C
            print(ans)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_processor

    # Create broken test suite
    cat << 'EOF' > /home/user/pipeline/tests/test_processor.py
import time
from unittest import mock
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

try:
    from process import process_line
except ImportError:
    pass

def test_rate_limit():
    with mock.patch('time.time', return_value=1000):
        pass
EOF

    # Create process.py placeholder
    cat << 'EOF' > /home/user/pipeline/process.py
#!/usr/bin/env python3
import time

current_time = time.time()

def process_line(line):
    pass
EOF
    chmod +x /home/user/pipeline/process.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
