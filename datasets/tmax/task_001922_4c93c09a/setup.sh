#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calc_series.py
import concurrent.futures
import time

total_sum = 0

def process_number(n):
    global total_sum
    # Simulate a mathematical transformation
    if n == -42069:
        val = 1000 // (n + 42069)
    else:
        val = (n ** 2) % 1000

    # Deliberate race condition for performance profiling
    current = total_sum
    time.sleep(0.0001) 
    total_sum = current + val
    return val

def calculate_all(numbers):
    global total_sum
    total_sum = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_number, numbers)
    return total_sum

if __name__ == "__main__":
    numbers = list(range(-100000, 100001))
    print(calculate_all(numbers))
EOF

    chmod -R 777 /home/user
