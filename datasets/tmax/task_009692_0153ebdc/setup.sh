#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious_parser.py
import threading
import json
import concurrent.futures
import time

lock_v1 = threading.Lock()
lock_v2 = threading.Lock()

parsed_results = []

def parse_line(line):
    line = line.strip()
    if not line:
        return

    # Bug: Inconsistent lock acquisition order causes deadlocks under high contention
    if line.startswith("FORMAT_V1:"):
        with lock_v1:
            time.sleep(0.01) # Simulate processing
            with lock_v2:
                data = line.split(":", 1)[1]
                parsed_results.append({"version": "v1", "data": data.strip()})
    elif line.startswith("FORMAT_V2:"):
        with lock_v2:
            time.sleep(0.01) # Simulate processing
            with lock_v1:
                data = line.split(":", 1)[1]
                parsed_results.append({"version": "v2", "data": data.strip()})

def main():
    with open('/home/user/sample.log', 'r') as f:
        lines = f.readlines()

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        executor.map(parse_line, lines)

    with open('/home/user/parsed_output.json', 'w') as f:
        json.dump(parsed_results, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/sample.log
FORMAT_V1: Initial boot sequence
FORMAT_V1: Loading modules
FORMAT_V2: User authentication success
FORMAT_V1: Establishing connection
FORMAT_V2: Key exchange initiated
FORMAT_V2: Session established
FORMAT_V1: Data transfer started
FORMAT_V2: Heartbeat check
FORMAT_V1: Connection closed
EOF

    cat << 'EOF' > /home/user/crash_dump.txt
Thread 0x00007f8a12ffd700 (most recent call first):
  File "/home/user/suspicious_parser.py", line 26 in parse_line
  File "/usr/lib/python3.10/concurrent/futures/thread.py", line 58 in run
  File "/usr/lib/python3.10/concurrent/futures/thread.py", line 83 in _worker

Thread 0x00007f8a137fe700 (most recent call first):
  File "/home/user/suspicious_parser.py", line 20 in parse_line
  File "/usr/lib/python3.10/concurrent/futures/thread.py", line 58 in run
  File "/usr/lib/python3.10/concurrent/futures/thread.py", line 83 in _worker
EOF

    chmod -R 777 /home/user
