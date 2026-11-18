#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app /opt/oracle

# Generate voicemail.wav using espeak
espeak -w /app/voicemail.wav "Hey, it's me. Here are the specs for the new sensor pipeline. We need to aggregate the data into fixed fifteen-minute tumbling windows based on the timestamp. For each fifteen minute bucket, calculate the mean temperature. Round the mean temperature to exactly two decimal places. Here is the critical part: our legacy sensors sometimes inject raw newline characters inside the 'status_log' column quotes. If any row contains an embedded newline character in the status_log, you must silently drop that entire row before doing any windowing or aggregations. Finally, output a JSON array of objects. Each object should have 'window_start' formatted as an ISO string, and 'mean_temp' as the rounded float. Only include windows that have at least one valid reading after dropping the corrupted ones. Thanks."

# Create oracle script
cat << 'EOF' > /opt/oracle/pipeline_oracle.py
import sys
import csv
import json
from datetime import datetime, timedelta

def run():
    content = sys.stdin.read()
    # Use csv module to correctly handle quoted newlines
    reader = csv.reader(content.splitlines(keepends=True))
    header = next(reader, None)

    buckets = {}

    for row in reader:
        if not row or len(row) < 4:
            continue
        timestamp_str, sensor_id, temp_str, status_log = row

        # Rule: Drop rows with embedded newlines in status_log
        if '\n' in status_log:
            continue

        try:
            dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            temp = float(temp_str)
        except ValueError:
            continue

        # 15-minute tumbling window
        minute_bucket = (dt.minute // 15) * 15
        bucket_dt = dt.replace(minute=minute_bucket, second=0, microsecond=0)
        bucket_str = bucket_dt.isoformat()
        if bucket_str.endswith('+00:00'):
            bucket_str = bucket_str.replace('+00:00', 'Z')

        if bucket_str not in buckets:
            buckets[bucket_str] = []
        buckets[bucket_str].append(temp)

    results = []
    for bucket in sorted(buckets.keys()):
        temps = buckets[bucket]
        mean_temp = sum(temps) / len(temps)
        results.append({
            "window_start": bucket,
            "mean_temp": round(mean_temp, 2)
        })

    print(json.dumps(results, separators=(',', ':')))

if __name__ == '__main__':
    run()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
