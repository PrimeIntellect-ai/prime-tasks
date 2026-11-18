#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_task.py
import sqlite3
import json
import base64
import os

db_path = "/home/user/corrupt_metrics.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE sensor_data (id INTEGER PRIMARY KEY, payload TEXT)")

vectors = [
    [1, 2, 3],
    [4, 5, 6],
    [-1, 0, 1],
    [2, -2, 2],
    [10, 20, 30]
]

for i, vec in enumerate(vectors, 1):
    # Serialize to JSON, then base64, then intentionally strip padding
    json_str = json.dumps(vec)
    b64_str = base64.b64encode(json_str.encode()).decode().rstrip('=')
    c.execute("INSERT INTO sensor_data (id, payload) VALUES (?, ?)", (i, b64_str))

conn.commit()
conn.close()

# Truncate the file slightly to make it "corrupted" but recoverable via .recover
with open(db_path, "ab") as f:
    f.write(b"GARBAGE_DATA_CORRUPTION_" * 100)
EOF

    python3 /home/user/setup_task.py
    rm /home/user/setup_task.py

    cat << 'EOF' > /home/user/process_math.py
import sqlite3
import json
import base64

def get_dot_product(v1, v2):
    # BUG: Calculates sum of additions instead of sum of multiplications
    return sum(a + b for a, b in zip(v1, v2))

def main():
    # Assuming the user recovers to a file named recovered.db or similar.
    # The user will need to update this path or pass the data.
    conn = sqlite3.connect('recovered.db')
    c = conn.cursor()
    c.execute("SELECT id, payload FROM sensor_data ORDER BY id")
    rows = c.fetchall()

    vectors = []
    for row in rows:
        payload = row[1]
        # BUG: Fails if padding is missing
        decoded = base64.b64decode(payload).decode()
        vec = json.loads(decoded)
        vectors.append(vec)

    total_sum = 0
    for i in range(len(vectors) - 1):
        total_sum += get_dot_product(vectors[i], vectors[i+1])

    print(f"Total Sum: {total_sum}")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
