#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv git
pip3 install pytest

mkdir -p /home/user/data_processor
cd /home/user/data_processor

# Create virtual environment and install dependencies if needed
python3 -m venv venv
. venv/bin/activate

# Initialize git
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create input.jsonl with a mix of valid and corrupted records
cat << 'EOF' > generate_data.py
import json
import random

with open("input.jsonl", "w") as f:
    for i in range(50000):
        if random.random() < 0.2:
            # Corrupted record (missing 'data' field)
            f.write(json.dumps({"id": i, "timestamp": 1600000000 + i}) + "\n")
        else:
            # Valid record
            f.write(json.dumps({"id": i, "timestamp": 1600000000 + i, "data": f"payload_{i}" * 10}) + "\n")
EOF
python3 generate_data.py
rm generate_data.py

# --- COMMIT 1 (v1.0) ---
cat << 'EOF' > processor.py
import json
import sys

def process_stream(filepath):
    processed_count = 0
    with open(filepath, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                if 'data' not in record:
                    raise ValueError("Corrupted record: missing 'data'")
                processed_count += 1
            except Exception as e:
                pass
    print(f"Processed {processed_count} valid records.")

if __name__ == "__main__":
    process_stream("input.jsonl")
EOF
git add processor.py
git commit -m "Initial commit of data processor"
git tag v1.0

# --- COMMIT 2 ---
cat << 'EOF' > processor.py
import json
import sys

def process_stream(filepath):
    processed_count = 0
    with open(filepath, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                if 'data' not in record:
                    raise ValueError("Corrupted record: missing 'data'")
                processed_count += 1
                if processed_count % 10000 == 0:
                    pass # Placeholder for logging
            except Exception as e:
                pass
    print(f"Processed {processed_count} valid records.")

if __name__ == "__main__":
    process_stream("input.jsonl")
EOF
git add processor.py
git commit -m "Add logging placeholder"

# --- COMMIT 3 (The Bug) ---
cat << 'EOF' > processor.py
import json
import sys

quarantine_record_cache = []

def process_stream(filepath):
    processed_count = 0
    with open(filepath, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                if 'data' not in record:
                    raise ValueError("Corrupted record: missing 'data'")
                processed_count += 1
                if processed_count % 10000 == 0:
                    pass
            except Exception as e:
                # Cache failed records for later inspection (Causes memory leak!)
                quarantine_record_cache.append(line)
                pass
    print(f"Processed {processed_count} valid records.")

if __name__ == "__main__":
    process_stream("input.jsonl")
EOF
git add processor.py
git commit -m "Add error handling and caching for failed records"
BAD_COMMIT_HASH=$(git rev-parse HEAD)

# --- COMMIT 4 ---
cat << 'EOF' > processor.py
import json
import sys
import time

quarantine_record_cache = []

def process_stream(filepath):
    processed_count = 0
    start_time = time.time()
    with open(filepath, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                if 'data' not in record:
                    raise ValueError("Corrupted record: missing 'data'")
                processed_count += 1
                if processed_count % 10000 == 0:
                    pass
            except Exception as e:
                quarantine_record_cache.append(line)
                pass
    duration = time.time() - start_time
    print(f"Processed {processed_count} valid records in {duration:.2f} seconds.")

if __name__ == "__main__":
    process_stream("input.jsonl")
EOF
git add processor.py
git commit -m "Add basic performance timing"

# Store the correct hash in a hidden file just for test verification script access later
echo "$BAD_COMMIT_HASH" > /home/user/.secret_bad_commit

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
