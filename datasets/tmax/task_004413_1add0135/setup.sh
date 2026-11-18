#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/legacy_aggregator

    # 1. Create input_data.csv
    python3 -c "
import random
with open('/home/user/legacy_aggregator/input_data.csv', 'w') as f:
    f.write('user_id,score\n')
    for i in range(1, 10001):
        f.write(f'{i},{10}\n')
"

    # 2. Create requirements.txt with a conflict
    cat << 'EOF' > /home/user/legacy_aggregator/requirements.txt
requests==2.31.0
urllib3==1.25.11
pandas==2.0.3
EOF

    # 3. Create the buggy main.py
    cat << 'EOF' > /home/user/legacy_aggregator/main.py
import pandas as pd
import threading
import sqlite3
from concurrent.futures import ThreadPoolExecutor

stats = {'total_score': 0, 'record_count': 0}

def process_chunk(chunk):
    global stats
    local_sum = chunk['score'].sum()
    local_count = len(chunk)

    # Bug: Race condition updating global state without a lock
    # A time.sleep(0.001) could be added to force the race condition if needed
    stats['total_score'] += local_sum
    stats['record_count'] += local_count

def main():
    df = pd.read_csv('input_data.csv')
    chunks = [df[i:i+100] for i in range(0, len(df), 100)]

    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_chunk, chunks)

    conn = sqlite3.connect('results.db')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS aggregate (total_score INTEGER, record_count INTEGER)')
    c.execute('DELETE FROM aggregate')
    c.execute('INSERT INTO aggregate (total_score, record_count) VALUES (?, ?)', 
              (int(stats['total_score']), int(stats['record_count'])))
    conn.commit()
    conn.close()
    print("Processing complete.")

if __name__ == '__main__':
    main()
EOF

    # 4. Create crash.dmp
    python3 -c "
import os
with open('/home/user/legacy_aggregator/crash.dmp', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'Some random text data... \n')
    f.write(b'AUTH_TOKEN=aB3dE6gH9jK2mN5p')
    f.write(os.urandom(1024))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
