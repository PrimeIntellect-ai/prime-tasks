#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/math_service.py
import threading
import time
import sys

sys.setrecursionlimit(500)

lock_A = threading.Lock()
lock_B = threading.Lock()

def compute_sequence(n):
    if n == 0: return 0
    if n == 1: return 1
    # Bug: negative n causes RecursionError
    return compute_sequence(n-1) + compute_sequence(n-2)

def process_request(req_id, n):
    try:
        if n % 2 == 0:
            with lock_A:
                time.sleep(0.01)
                with lock_B:
                    res = compute_sequence(n)
        else:
            with lock_B:
                time.sleep(0.01)
                with lock_A:
                    res = compute_sequence(n)
        return res
    except Exception as e:
        print(f"Error processing {req_id}: {e}")
        raise
EOF

    cat << 'EOF' > /home/user/service.log
[2023-10-27 10:00:01] [Thread-1] Received request ID 1001 for n=5
[2023-10-27 10:00:01] [Thread-2] Received request ID 1002 for n=-3
[2023-10-27 10:00:01] [Thread-1] Acquired lock_B
[2023-10-27 10:00:01] [Thread-2] Acquired lock_A
[2023-10-27 10:00:02] [Thread-1] Waiting for lock_A
[2023-10-27 10:00:02] [Thread-2] Waiting for lock_B
[2023-10-27 10:01:05] [Thread-3] Received request ID 1005 for n=-5
[2023-10-27 10:01:05] [Thread-3] Exception: RecursionError: maximum recursion depth exceeded
Traceback (most recent call last):
  File "math_service.py", line 14, in compute_sequence
    return compute_sequence(n-1) + compute_sequence(n-2)
[2023-10-27 10:02:10] [Thread-4] Received request ID 1009 for n=10
[2023-10-27 10:02:10] [Thread-5] Received request ID 1012 for n=-1
[2023-10-27 10:02:11] [Thread-5] Exception: RecursionError: maximum recursion depth exceeded
EOF

    chmod -R 777 /home/user
