#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import csv
import uuid
import random
import hashlib
from datetime import datetime, timedelta

random.seed(42)

event_types = ['login', 'purchase', 'view', 'logout']
users = [f"user_{i}" for i in range(100)]

records = []
# Generate base records
for i in range(10000):
    user_id = random.choice(users)
    event_type = random.choice(event_types)
    payload = f"data_{random.randint(1, 1000)}"
    timestamp = (datetime(2023, 1, 1) + timedelta(minutes=i)).isoformat()
    event_id = str(uuid.uuid4())
    records.append([event_id, user_id, event_type, timestamp, payload])

# Inject duplicates (simulating ETL retries)
final_records = []
for r in records:
    final_records.append(r)
    if random.random() < 0.3:  # 30% chance to duplicate
        # duplicate with new event_id and timestamp but same user, type, payload
        dup = list(r)
        dup[0] = str(uuid.uuid4())
        dup[3] = (datetime.fromisoformat(r[3]) + timedelta(seconds=random.randint(1,60))).isoformat()
        final_records.append(dup)

# Shuffle slightly to mix duplicates
random.shuffle(final_records)

with open('/home/user/data/raw_events.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['event_id', 'user_id', 'event_type', 'timestamp', 'payload'])
    writer.writerows(final_records)

EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
