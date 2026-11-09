#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/worker.py
def calculate_weight(n):
    # BUG: missing base case for n <= 0
    if n == 1:
        return 1
    if n == 2:
        return 2
    return calculate_weight(n - 1) + calculate_weight(n - 2)
EOF

    cat << 'EOF' > /home/user/run_system.py
import os
import sys
from worker import calculate_weight

def main():
    log_file = "/home/user/logs/run_after.log"
    with open(log_file, "w") as f:
        try:
            res = calculate_weight(-3)
            f.write(f"[2023-10-15T08:05:00] TASK_EVENT ID:4 STATUS:SUCCESS RESULT:{res}\n")
        except Exception as e:
            f.write(f"[2023-10-15T08:05:00] TASK_EVENT ID:4 STATUS:FAILED ERROR:{type(e).__name__}\n")
            sys.exit(1)

        res = calculate_weight(5)
        f.write(f"[2023-10-15T08:06:00] TASK_EVENT ID:5 STATUS:SUCCESS RESULT:{res}\n")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/logs/producer_before.log
[2023-10-15T08:00:00] PRODUCER starting up
[2023-10-15T08:01:00] TASK_EVENT ID:1 STATUS:QUEUED
[2023-10-15T08:02:00] TASK_EVENT ID:2 STATUS:QUEUED
[2023-10-15T08:03:00] TASK_EVENT ID:3 STATUS:QUEUED
EOF

    cat << 'EOF' > /home/user/logs/worker_before.log
[2023-10-15T08:01:30] TASK_EVENT ID:1 STATUS:SUCCESS RESULT:1
[2023-10-15T08:02:30] TASK_EVENT ID:2 STATUS:SUCCESS RESULT:2
[2023-10-15T08:04:00] TASK_EVENT ID:3 STATUS:FAILED ERROR:RecursionError
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
