#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_data.py
import csv
import os

data = [
    ["1600000001", "s1", "10.0", "System startup"],
    ["1600000001", "s2", "50.0", "System startup"],
    ["1600000002", "s1", "", "CPU spike\nInvestigation required"],
    ["1600000002", "s2", "60.0", "Normal"],
    ["1600000003", "s1", "20.0", "Recovered"],
    ["1600000003", "s2", "", "Disk I/O error\nNeeds replacement\nUrgent"],
    ["1600000004", "s1", "30.0", "Normal"],
    ["1600000004", "s2", "40.0", "Normal"],
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/server_logs.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "server_id", "cpu_usage", "log_message"])
    writer.writerows(data)
EOF

python3 /tmp/setup_data.py
rm /tmp/setup_data.py

chmod -R 777 /home/user
