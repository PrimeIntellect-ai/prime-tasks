#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv
import json
import random
from datetime import datetime, timedelta

def generate_csv():
    services = ['nginx', 'postgres', 'redis', 'app-backend']
    data = []

    base_time = datetime(2023, 10, 1, 12, 0, 0)

    # Deterministic generation
    random.seed(42)

    for i in range(1, 1001):
        ts = base_time + timedelta(minutes=random.randint(1, 10000))
        svc = random.choice(services)

        # Create a multiline diff
        additions = [f"config_var_{random.randint(100, 999)} = {random.choice(['true', 'false', '1', '0'])}" for _ in range(random.randint(0, 3))]
        deletions = [f"old_var_{random.randint(10, 99)} = {random.choice(['true', 'false'])}" for _ in range(random.randint(0, 2))]

        diff_lines = ["--- old", "+++ new"]
        for d in deletions:
            diff_lines.append(f"- {d}")
        for a in additions:
            diff_lines.append(f"+ {a}")

        random.shuffle(diff_lines[2:]) # mix additions and deletions
        diff_text = "\n".join(diff_lines)

        data.append({
            'id': i,
            'timestamp': ts.isoformat() + "Z",
            'service': svc,
            'diff': diff_text
        })

    with open('/home/user/config_drifts.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['id', 'timestamp', 'service', 'diff'])
        writer.writeheader()
        writer.writerows(data)

    # Generate Golden JSON for verification
    golden = {}

    # Sort data by timestamp first
    data.sort(key=lambda x: x['timestamp'])

    for row in data:
        svc = row['service']
        if svc not in golden:
            golden[svc] = []

        diff_lines = row['diff'].split('\n')
        for line in diff_lines:
            if line.startswith('+ '):
                golden[svc].append(line[2:])

    with open('/home/user/.golden_summary.json', 'w') as f:
        json.dump(golden, f)

if __name__ == '__main__':
    generate_csv()
EOF

    python3 /home/user/setup_data.py

    chmod -R 777 /home/user
