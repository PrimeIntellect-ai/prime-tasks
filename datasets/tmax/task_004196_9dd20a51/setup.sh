#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest flask fastapi uvicorn requests

    mkdir -p /app/vendor/csv-time-bucketer-1.2.0/csv_time_bucketer

    cat << 'EOF' > /app/vendor/csv-time-bucketer-1.2.0/setup.py
from setuptools impor setup, find_packages

setup(
    name='csv-time-bucketer',
    version='1.2.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/vendor/csv-time-bucketer-1.2.0/csv_time_bucketer/__init__.py
def bucket_by_hour(records, time_key):
    from collections import defaultdict
    buckets = defaultdict(list)
    for record in records:
        dt_str = record.get(time_key)
        if dt_str and len(dt_str) >= 13:
            # Extract up to the hour: YYYY-MM-DDTHH
            hour_bucket = dt_str[:13]
            buckets[hour_bucket].append(record)
    return dict(buckets)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
