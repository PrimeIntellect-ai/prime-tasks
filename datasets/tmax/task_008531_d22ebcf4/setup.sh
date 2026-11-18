#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import random

os.makedirs("/home/user/app", exist_ok=True)

with open("/home/user/app/crash_dump.bin", "wb") as f:
    for _ in range(5000):
        f.write(os.urandom(random.randint(10, 50)))
        log_line = b"UPTIME_PING=10\n"
        f.write(log_line)
    f.write(os.urandom(100))

aggregator_code = """import concurrent.futures
import sys
import time

total_uptime = 0

def process_chunk(chunk):
    global total_uptime
    local_sum = sum(int(line.split("=")[1]) for line in chunk if "UPTIME_PING" in line)
    # Artificial delay to ensure race condition manifests consistently without locks
    time.sleep(0.01)
    total_uptime += local_sum

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 aggregator.py <logfile>")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        lines = f.readlines()

    chunk_size = 100
    chunks = [lines[i:i + chunk_size] for i in range(0, len(lines), chunk_size)]

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_chunk, chunks)

    print(f"Total Uptime: {total_uptime}")

if __name__ == "__main__":
    main()
"""

with open("/home/user/app/aggregator.py", "w") as f:
    f.write(aggregator_code)
'

    chmod -R 777 /home/user
