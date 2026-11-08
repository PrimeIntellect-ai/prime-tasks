#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas pyarrow pydantic

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)
start_time = datetime(2023, 1, 1, 12, 0, 0)

data = []
# 100 valid rows for SENS-0042 (sum = 150.0)
# We will just generate 99 random values and force the 100th to make the sum exactly 150.0
vals_42 = [random.uniform(0.5, 2.5) for _ in range(99)]
vals_42.append(150.0 - sum(vals_42))

for i, v in enumerate(vals_42):
    t = (start_time + timedelta(minutes=i)).isoformat()
    data.append(["SENS-0042", t, round(v, 4)])

# 50 valid rows for SENS-0011
for i in range(50):
    t = (start_time + timedelta(minutes=100+i)).isoformat()
    data.append(["SENS-0011", t, round(random.uniform(-5, 5), 4)])

# 15 invalid rows
# 5 bad IDs
for i in range(5):
    data.append(["SENS-A042", start_time.isoformat(), 1.0])
# 5 bad dates
for i in range(5):
    data.append(["SENS-0012", "not-a-date", 1.0])
# 5 out of bounds
for i in range(5):
    data.append(["SENS-0013", start_time.isoformat(), 15.0])

random.shuffle(data)

with open('/home/user/raw_sensor_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["sensor_id", "timestamp", "raw_value"])
    writer.writerows(data)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
