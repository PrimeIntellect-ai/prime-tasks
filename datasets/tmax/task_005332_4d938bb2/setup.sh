#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pydantic

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import json
import random

random.seed(42)

regions = ["Tundra", "Rainforest", "Desert", "Taiga", "Savanna"]

with open("/home/user/observations.jsonl", "w") as f:
    for i in range(50000):
        # 3 different schema versions
        version = random.choice(["v1", "v2", "v3"])
        region = random.choice(regions)
        sensor_id = f"sens_{random.randint(1, 1000)}"

        if version == "v1":
            record = {
                "schema": "v1",
                "meta": {"state": random.choice(["active", "inactive", "broken"]), "id": sensor_id},
                "location": {"biome": region},
                "data": {"temp_c": random.uniform(-20, 40)}
            }
        elif version == "v2":
            record = {
                "schema": "v2",
                "device_info": {"status": random.choice(["calibrated", "uncalibrated"]), "uuid": sensor_id},
                "geo": {"region_name": region},
                "readings": {"temperature": {"value": random.uniform(-20, 40), "unit": "C"}}
            }
        else:
            # v3 is invalid/noise, missing temperature or in Fahrenheit
            record = {
                "schema": "v3",
                "sensor_status": "active",
                "id": sensor_id,
                "biome": region,
                "temp_f": random.uniform(0, 100)
            }

        f.write(json.dumps(record) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
