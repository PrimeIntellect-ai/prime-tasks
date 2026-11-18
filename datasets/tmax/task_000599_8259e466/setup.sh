#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data

    # Create 50 valid JSON files
    for i in $(seq 1 50); do
        echo "{\"id\": $i, \"values\": [10, 20, 30]}" > /home/user/sensor_data/sensor_${i}.json
    done

    # Create 2 corrupted JSON files
    echo '{"id": 98, "values": [10, 20, 30' > /home/user/sensor_data/sensor_98.json
    echo '{"id": 99, "values": 10, 20]}' > /home/user/sensor_data/sensor_99.json

    # Create the buggy script
    cat << 'EOF' > /home/user/process_sensors.py
import concurrent.futures
import json
import glob
import os

def process_subtask(data_chunk):
    # Simulates some heavy data transformation
    return sum(data_chunk)

def process_file(filepath, executor):
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        # Bug 2: Livelock on corrupted data
        retry = True
        while retry:
            pass # Stuck forever
        return 0

    # Bug 1: Deadlock if thread pool is full
    # Waits for subtask to finish on the SAME executor
    future = executor.submit(process_subtask, data['values'])
    return future.result()

def main():
    files = glob.glob('/home/user/sensor_data/*.json')
    results = []

    # max_workers=4, and we submit >4 tasks. The outer tasks take up all workers 
    # and then block waiting for inner tasks, resulting in starvation deadlock.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(process_file, f, executor): f for f in files}
        for future in concurrent.futures.as_completed(futures):
            try:
                res = future.result()
                if res is not None:
                    results.append(res)
            except Exception as e:
                pass

    with open('/home/user/final_aggregate.json', 'w') as f:
        json.dump({"total": sum(results)}, f)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
