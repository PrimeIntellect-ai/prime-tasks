#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest "pandas>=2.0.0"

    mkdir -p /home/user
    cd /home/user

    # Create the data.jsonl file without using double braces to avoid Apptainer template variable conflicts
    python3 -c '
with open("data.jsonl", "w") as f:
    for i in range(1000):
        if i % 10 == 0:
            f.write("{\"id\": " + str(i) + ", \"value\": " + str(i) + ",}\n")
        else:
            f.write("{\"id\": " + str(i) + ", \"value\": " + str(i) + "}\n")
'

    # Create the process.py script
    cat << 'EOF' > process.py
import json
import threading
from concurrent.futures import ThreadPoolExecutor
import pandas as pd
import time

total_valid_records = 0

def process_line(line):
    global total_valid_records

    record = json.loads(line)

    if "value" in record:
        temp = total_valid_records
        time.sleep(0.001)
        total_valid_records = temp + 1

def main():
    df = pd.DataFrame()
    df = df.append({'status': 'started'}, ignore_index=True)

    with open('/home/user/data.jsonl', 'r') as f:
        lines = f.readlines()

    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_line, lines)

    with open('/home/user/output.txt', 'w') as f:
        f.write(str(total_valid_records))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
