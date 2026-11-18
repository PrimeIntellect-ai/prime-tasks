#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create the SQLite database with edge-case data
    cat << 'EOF' > create_db.py
import sqlite3

conn = sqlite3.connect('telemetry.db')
c = conn.cursor()
c.execute('CREATE TABLE logs (id INTEGER PRIMARY KEY, latency REAL, status TEXT)')

# Insert normal high-base data (causes catastrophic cancellation in naive variance)
base = 10000000.0
data = [
    (base + 0.001, 'OK'),
    (base + 0.003, 'OK'),
    (base + 0.002, 'OK'),
    (base + 0.005, 'OK'),
    (base + 0.004, 'OK'),
    (base + 0.006, 'OK'),
]

# Insert edge cases (causes NULL/negative issues)
data.extend([
    (None, 'OK'),
    (-5.0, 'OK'),
    (15.0, 'ERROR'),
    (None, 'ERROR')
])

c.executemany('INSERT INTO logs (latency, status) VALUES (?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 create_db.py
    rm create_db.py

    # 2. Create the buggy anomaly_detector.py
    cat << 'EOF' > anomaly_detector.py
import sqlite3
import math

def fetch_data():
    conn = sqlite3.connect('/home/user/telemetry.db')
    c = conn.cursor()
    # BUG 1: Fetches NULLs, negatives, and non-OK statuses
    c.execute("SELECT latency FROM logs")
    # This will crash when trying to do math on None, or process bad data
    data = [row[0] for row in c.fetchall()]
    conn.close()
    return data

def calculate_variance(data):
    n = len(data)
    if n == 0: return 0
    sum_x = sum(data)
    sum_x2 = sum(x*x for x in data)

    # BUG 2: Catastrophic cancellation for large values with small diffs
    # Will result in negative variance, causing math domain error in sqrt later
    variance = (sum_x2 - (sum_x**2)/n) / n
    return variance

def calibrate_threshold(variance):
    # BUG 3: Will crash if variance < 0, and fails to converge properly
    base_thresh = math.sqrt(variance)

    val = 0.0
    learning_rate = 0.5

    for i in range(100):
        # Naive oscillation that might fail to converge
        diff = base_thresh - val
        val += learning_rate * diff

        # Missing absolute value and strict check, leading to failure
        if diff == 0.0:
            return val

    raise RuntimeError("Failed to converge")

if __name__ == "__main__":
    data = fetch_data()
    # Temporary hack so script runs initially but produces wrong math
    data = [d for d in data if d is not None] 

    var = calculate_variance(data)
    threshold = calibrate_threshold(var)
    print(threshold)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
