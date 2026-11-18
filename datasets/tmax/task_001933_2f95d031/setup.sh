#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import json
import random

random.seed(42)

def generate_data():
    records = []

    # Generate 300 valid views + 10 exact duplicates
    for i in range(300):
        records.append({"user_id": f"u{random.randint(100,999)}", "item_id": f"i{random.randint(10,99)}", "action": random.choice(["VIEW", "viewed", "View"]), "timestamp": 1600000000 + i})
    for i in range(10):
        # duplicate of the first 10
        records.append(records[i].copy())

    # Generate 150 valid clicks + 5 exact duplicates
    clicks_start = len(records)
    for i in range(150):
        records.append({"user_id": f"u{random.randint(100,999)}", "item_id": f"i{random.randint(10,99)}", "action": random.choice(["CLICK", "Clicked"]), "timestamp": 1600005000 + i})
    for i in range(5):
        records.append(records[clicks_start + i].copy())

    # Generate 80 purchases (no duplicates)
    for i in range(80):
        records.append({"user_id": f"u{random.randint(100,999)}", "item_id": f"i{random.randint(10,99)}", "action": random.choice(["Purchase", "buy", "BUYING"]), "timestamp": 1600010000 + i})

    # Generate 20 records with missing fields
    for i in range(10):
        records.append({"user_id": f"u100", "action": "view", "timestamp": 1600000000}) # missing item_id
        records.append({"item_id": f"i10", "action": "click", "timestamp": 1600000000}) # missing user_id

    # Generate 15 records with unknown actions
    for i in range(15):
        records.append({"user_id": f"u200", "item_id": f"i20", "action": "SCROLL", "timestamp": 1600020000 + i})

    # Shuffle everything to make it realistic
    random.shuffle(records)

    with open('/home/user/raw_events.jsonl', 'w') as f:
        for r in records:
            f.write(json.dumps(r) + '\n')

generate_data()
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
