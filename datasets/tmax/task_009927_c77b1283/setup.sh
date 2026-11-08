#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
from datetime import datetime, timedelta

os.makedirs("/home/user/workspace", exist_ok=True)
os.makedirs("/home/user/raw_logs/sensor_logs", exist_ok=True)

start_time = datetime(2023, 1, 1, 10, 0, 0)

records_data = []
# Generate 25 records. 5 will be ERROR/CALIBRATING. 20 will be OK.
# This will result in exactly 2 chunk files of 10 records each.
statuses = ["OK"] * 4 + ["ERROR"] + ["OK"] * 5 + ["CALIBRATING"] + ["OK"] * 11 + ["ERROR"] + ["OK", "OK"]

for i, status in enumerate(statuses):
    ts = start_time + timedelta(minutes=i*5)
    records_data.append({
        "ts": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ts_clean": ts.strftime("%Y%m%d_%H%M%S"),
        "id": f"S-{100+i}",
        "status": status,
        "reading": f"{20.5 + i*0.1:.2f}"
    })

def write_records(filename, recs):
    with open(filename, 'w') as f:
        for r in recs:
            f.write("===BEGIN_RECORD===\n")
            f.write(f"Timestamp: {r['ts']}\n")
            f.write(f"SensorID: {r['id']}\n")
            f.write(f"Status: {r['status']}\n")
            f.write(f"Reading: {r['reading']}\n")
            f.write("===END_RECORD===\n")

write_records("/home/user/raw_logs/sensor_logs/log_A.log", records_data[0:10])
write_records("/home/user/raw_logs/sensor_logs/log_B.log", records_data[10:20])
write_records("/home/user/raw_logs/sensor_logs/log_C.log", records_data[20:25])

# Create tar.gz
with tarfile.open("/home/user/raw_data.tar.gz", "w:gz") as tar:
    tar.add("/home/user/raw_logs/sensor_logs", arcname="sensor_logs")

os.system("rm -rf /home/user/raw_logs")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
