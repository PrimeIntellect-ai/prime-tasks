#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/profiler
    cd /home/user/profiler

    # 1. Create requirements.txt with a conflict
    cat << 'EOF' > requirements.txt
pandas==2.0.3
numpy==1.21.0
# numpy 1.21.0 is generally incompatible with pandas 2.0.3 on newer python versions, or at least causes a resolver conflict if other packages are added.
# Let's make a hard conflict:
requests==2.31.0
urllib3<1.26
EOF

    # 2. Create a corrupted DB but valid WAL
    # We use a python script and os._exit(0) to prevent clean shutdown, ensuring the WAL file is not deleted.
    python3 -c "
import sqlite3, os
conn = sqlite3.connect('init.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE measurements (id INTEGER PRIMARY KEY, timestamp TEXT, cpu_usage REAL)')
conn.commit()
conn.execute(\"INSERT INTO measurements (timestamp, cpu_usage) VALUES ('2023-10-01T10:00:00', 45.0), ('2023-10-01T10:01:00', 55.0), ('2023-10-01T10:02:00', 65.0), ('2023-10-01T10:03:00', 70.0), ('2023-10-01T10:04:00', 60.0)\")
conn.commit()
os._exit(0)
"

    # Copy out to metrics.db
    cp init.db metrics.db
    cp init.db-wal metrics.db-wal
    cp init.db-shm metrics.db-shm || true

    # Corrupt the main DB file by overwriting its first 100 bytes (header)
    dd if=/dev/zero of=metrics.db bs=100 count=1 conv=notrunc

    # 3. Create the buggy python script
    cat << 'EOF' > process_metrics.py
import sqlite3
import json
import argparse
import pandas as pd

def compute_ema(data_series, span):
    # BUG: alpha is inverted
    alpha = (span + 1) / 2.0

    # In pandas, we can just use ewm, but this script calculates it manually for the test
    ema = []
    for i, val in enumerate(data_series):
        if i == 0:
            ema.append(val)
        else:
            ema.append(alpha * val + (1 - alpha) * ema[-1])
    return ema

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    df = pd.read_sql_query("SELECT * FROM measurements ORDER BY id", conn)

    ema_values = compute_ema(df['cpu_usage'].tolist(), span=3)

    result = {
        "span": 3,
        "ema": [round(x, 2) for x in ema_values]
    }

    with open(args.out, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    chmod +x process_metrics.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
