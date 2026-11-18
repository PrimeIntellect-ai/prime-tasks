#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB with base64 encoded JSON payloads
    cat << 'EOF' > setup_db.py
import sqlite3
import json
import base64

conn = sqlite3.connect('metrics.db')
c = conn.cursor()
c.execute('CREATE TABLE sensor_data (id INTEGER PRIMARY KEY, payload TEXT)')

# Values designed to cause catastrophic cancellation in naive E[x^2] - (E[x])^2
# variance calculation (due to float precision loss)
temperatures = [100000000.1, 100000000.2, 100000000.3, 100000000.4, 100000000.5]

for i, temp in enumerate(temperatures):
    data = {"sensor": "temp_1", "temperature": temp}
    json_str = json.dumps(data)
    # base64 encode the payload
    b64_str = base64.b64encode(json_str.encode('utf-8')).decode('utf-8')
    c.execute('INSERT INTO sensor_data (payload) VALUES (?)', (b64_str,))

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    # Create the buggy aggregator script
    cat << 'EOF' > aggregator.py
import sqlite3
import json
import math
import base64
import os

def get_variance(data):
    # Naive variance calculation: E[x^2] - (E[x])^2
    # This will fail with catastrophic cancellation for our data
    n = len(data)
    if n == 0:
        return 0
    sum_x = sum(data)
    sum_x2 = sum(x**2 for x in data)
    mean = sum_x / n
    variance = (sum_x2 / n) - (mean**2)
    # Rounding errors make variance negative, math.sqrt throws domain error
    std_dev = math.sqrt(variance) 
    return variance

def main():
    conn = sqlite3.connect('/home/user/metrics.db')
    c = conn.cursor()
    c.execute('SELECT payload FROM sensor_data')

    temps = []
    for row in c.fetchall():
        payload_raw = row[0]
        # BUG 1: Fails to base64 decode
        # The correct fix: json_str = base64.b64decode(payload_raw).decode('utf-8')
        try:
            data = json.loads(payload_raw)
            temps.append(data['temperature'])
        except Exception as e:
            # print(f"Parsing error: {e}")
            pass # Silent failure for parsing

    if temps:
        # BUG 2: Numerical instability in get_variance
        var = get_variance(temps)

        # BUG 3: Tries to write to a non-existent directory and swallows error
        try:
            with open('/home/user/hidden_output_dir/metrics_out.json', 'w') as f:
                json.dump({"temperature_variance": var}, f)
        except IOError:
            pass

if __name__ == "__main__":
    main()
EOF
    chmod +x aggregator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
