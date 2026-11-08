#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random
import time

random.seed(42)

def make_data():
    base_time = 1696118400 # 2023-10-01 00:00:00 UTC
    data = []

    # Generate true records
    for day in range(5):
        for sensor in ["S1", "S2"]:
            for hr in range(24):
                if random.random() < 0.2: continue # Missing data

                event_time_str = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(base_time + day*86400 + hr*3600))
                temp = round(random.uniform(20.0, 30.0), 1)
                ingested = int(time.time()) - random.randint(1000, 5000)

                data.append((event_time_str, sensor, temp, ingested))

                # ETL retry duplicates (same event/sensor/temp, newer ingestion)
                if random.random() < 0.3:
                    data.append((event_time_str, sensor, temp, ingested + 600))

    random.shuffle(data)

    # Split into 3 shards
    shards = [data[i::3] for i in range(3)]
    for i, shard in enumerate(shards):
        with open(f"/home/user/sensor_data/shard_{i+1}.csv", "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["event_time", "sensor_id", "temperature", "ingested_at"])
            writer.writerows(shard)

make_data()
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
