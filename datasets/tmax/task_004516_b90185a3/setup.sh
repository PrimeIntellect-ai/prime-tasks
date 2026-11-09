#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /app

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import os
import json
import concurrent.futures
import sys

def parse_wal_chunk(chunk, events=None):
    if events is None:
        events = []
    for line in chunk:
        parts = line.strip().split(',', 3)
        if len(parts) >= 3:
            ts = float(parts[0])
            op = parts[1]
            key = parts[2]
            val = parts[3] if len(parts) > 3 else None
            events.append((ts, op, key, val))
    return events

def process_wal_dir(directory):
    files = [os.path.join(directory, f) for f in os.listdir(directory) if os.path.isfile(os.path.join(directory, f))]
    all_events = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = []
        for f in files:
            with open(f, 'r') as file:
                lines = file.readlines()
                chunk_size = 100
                for i in range(0, len(lines), chunk_size):
                    futures.append(executor.submit(parse_wal_chunk, lines[i:i+chunk_size]))
        for future in concurrent.futures.as_completed(futures):
            all_events.extend(future.result())

    all_events.sort(key=lambda x: x[0])

    state = {}
    for ts, op, key, val in all_events:
        if op == 'INSERT' or op == 'UPDATE':
            state[key] = val
        elif op == 'DELETE':
            state.pop(key, None)
    return state

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(json.dumps(process_wal_dir(sys.argv[1]), sort_keys=True))
EOF
    chmod +x /app/oracle_processor

    # Create vendored package repo
    mkdir -p /app/wal_processor
    cd /app/wal_processor
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev User"

    # Copy oracle as the initial good version
    cp /app/oracle_processor ./processor.py
    # Remove shebang for the module
    sed -i '1d' processor.py

    git add processor.py
    git commit -m "Initial commit"

    # Create history of good commits
    for i in $(seq 1 150); do
        echo "# feature update $i" >> processor.py
        git commit -am "Add minor feature $i"
    done

    # Introduce the bug
    sed -i 's/def parse_wal_chunk(chunk, events=None):/def parse_wal_chunk(chunk, events=[]):/' processor.py
    sed -i '/if events is None:/d' processor.py
    sed -i '/events = \[\]/d' processor.py
    git commit -am "Refactor parse_wal_chunk default arguments"

    # Create history of commits after the bug
    for i in $(seq 151 200); do
        echo "# feature update $i" >> processor.py
        git commit -am "Add minor feature $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
