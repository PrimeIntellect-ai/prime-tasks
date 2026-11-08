#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/finance_aggregator.py
import threading
import time
import random

class NetworkError(Exception):
    pass

# Mock data configuration
NUM_BATCHES = 10
RECORDS_PER_BATCH = 1000

global_records = 0
global_value = 0.0

def do_fetch(batch_id):
    # Simulate a network error occasionally
    if random.random() < 0.2:
        raise NetworkError("Connection reset")

    # Return mock records: value is exactly 0.1 per record
    return [{"id": i, "value": 0.1} for i in range(RECORDS_PER_BATCH)]

def fetch_data(batch_id):
    retries = 0
    while retries < 5:
        try:
            return do_fetch(batch_id)
        except NetworkError:
            # BUG 1: Missing retries += 1
            # retries += 1
            time.sleep(0.01)
            continue
    return []

def process_batch(batch_id):
    global global_records, global_value
    records = fetch_data(batch_id)

    for r in records:
        # BUG 2 & 3: Race condition without lock, and floating point inaccuracy
        # Should use a lock and decimal.Decimal
        temp_val = global_value
        temp_rec = global_records

        # Simulate slight processing delay to force race condition
        time.sleep(0.00001)

        global_value = temp_val + r["value"]
        global_records = temp_rec + 1

def main():
    random.seed(42)
    threads = []

    for i in range(NUM_BATCHES):
        t = threading.Thread(target=process_batch, args=(i,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    with open("/home/user/results.txt", "w") as f:
        f.write(f"Total Records: {global_records}\n")
        f.write(f"Total Value: {global_value}\n")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
