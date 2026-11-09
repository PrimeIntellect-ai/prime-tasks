#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import json

with open("/home/user/server_logs.jsonl", "w") as f:
    for hour in range(24):
        # Base count for the hour
        count = 10
        if hour == 12:
            count = 30 # Anomaly! Previous 3 hours (9, 10, 11) have 10 each. Avg = 10.0. 30 > 2*10.

        for m in range(count):
            time_str = f"2023-10-01T{hour:02d}:{m:02d}:00Z"
            f.write(json.dumps({"timestamp": time_str, "agent": "Mozilla/5.0"}) + "\n")

        # Inject bad lines in some hours
        if hour == 12:
            # Inject 15 bad lines. If they don't filter them, count is 45.
            for m in range(15):
                time_str = f"2023-10-01T{hour:02d}:{m+30:02d}:00Z"
                bad_json = '{"timestamp": "' + time_str + '", "agent": "BadBot\\\\uZZZZ"}'
                f.write(bad_json + "\n")

        if hour == 5:
            # Inject 5 bad lines
            for m in range(5):
                time_str = f"2023-10-01T{hour:02d}:{m+10:02d}:00Z"
                bad_json = '{"timestamp": "' + time_str + '", "agent": "BadBot\\\\uX123"}'
                f.write(bad_json + "\n")

EOF
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
