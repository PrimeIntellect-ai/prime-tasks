#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/app

    # Create SQLite database
    sqlite3 /home/user/app/metrics.db <<EOF
CREATE TABLE multipliers (id TEXT, value REAL);
INSERT INTO multipliers (id, value) VALUES ('alpha', 2.5);
EOF

    # Create input data (Base64 encoded JSON)
    echo -n '[{"val": 10}, {"val": 20}]' | base64 > /home/user/app/input.b64

    # Create environment file
    cat << 'EOF' > /home/user/app/env.sh
export APP_ENV="production"
export SCALE_FACTOR="0,5"
EOF

    # Create the Python script with bugs
    cat << 'EOF' > /home/user/app/calculate_metrics.py
import os
import json
import base64
import sqlite3

def main():
    scale_factor_str = os.environ.get("SCALE_FACTOR", "1.0")
    try:
        scale_factor = float(scale_factor_str)
    except ValueError:
        print(f"CRITICAL: Invalid SCALE_FACTOR: {scale_factor_str}")
        exit(1)

    with open("/home/user/app/input.b64", "r") as f:
        raw_data = f.read()

    # Bug 1: Wrong decoding charset
    decoded_json = base64.b64decode(raw_data).decode('utf-16')
    metrics = json.loads(decoded_json)

    conn = sqlite3.connect("/home/user/app/metrics.db")
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM multipliers WHERE id='alpha'")

    # Bug 2: Returns a tuple, not a float
    mult = cursor.fetchone()

    total = 0.0
    for item in metrics:
        # This will throw a TypeError if mult is a tuple
        total += item['val'] * mult

    final_result = total / scale_factor
    print(final_result)

if __name__ == "__main__":
    main()
EOF

    # Create runner script
    cat << 'EOF' > /home/user/app/run_job.sh
#!/bin/bash
source /home/user/app/env.sh
python3 /home/user/app/calculate_metrics.py
EOF

    chmod +x /home/user/app/run_job.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
