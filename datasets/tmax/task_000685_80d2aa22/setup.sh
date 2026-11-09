#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/audio /app/data /app/bin

    # Generate audio memo
    espeak -w /app/audio/config_memo.wav "The system is being updated. Apply a time offset of minus forty five minutes to all streams. Only aggregate data for the location Ciudad de México."

    # Create sensor catalog in UTF-16LE
    cat << 'EOF' > /app/data/sensor_catalog.txt
sensor_id,location_name,base_threshold
A1B,Ciudad de México,50.0
X99,New York,40.0
J22,東京,60.0
K44,Ciudad de México,55.0
EOF
    iconv -f UTF-8 -t UTF-16LE /app/data/sensor_catalog.txt > /app/data/sensor_catalog.csv
    rm /app/data/sensor_catalog.txt

    # Create oracle binary
    cat << 'EOF' > /app/bin/oracle_stream_processor
#!/usr/bin/env python3
import sys
import json
import csv
from datetime import datetime, timedelta

def main():
    catalog = {}
    with open('/app/data/sensor_catalog.csv', 'r', encoding='utf-16le') as f:
        reader = csv.DictReader(f)
        for row in reader:
            catalog[row['sensor_id']] = row['location_name']

    target_location = "Ciudad de México"
    offset = timedelta(minutes=-45)

    data = {}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        record = json.loads(line)
        sensor_id = record['sensor_id']

        if catalog.get(sensor_id) != target_location:
            continue

        ts_str = record['timestamp'].replace('Z', '+00:00')
        dt = datetime.fromisoformat(ts_str)

        dt += offset

        minute = (dt.minute // 15) * 15
        bucket_dt = dt.replace(minute=minute, second=0, microsecond=0)
        bucket_str = bucket_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        key = (bucket_str, sensor_id)
        if key not in data:
            data[key] = []
        data[key].append(record['value'])

    results = []
    for (bucket, sensor_id), values in data.items():
        results.append({
            "bucket": bucket,
            "sensor_id": sensor_id,
            "reading_count": len(values),
            "mean_value": round(sum(values) / len(values), 2),
            "max_value": round(max(values), 2)
        })

    results.sort(key=lambda x: (x["bucket"], x["sensor_id"]))
    print(json.dumps(results))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/bin/oracle_stream_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
