#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest networkx

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)

edges = [
    ("User_Alice", "User_Bob"),
    ("User_Bob", "User_Charlie"),
    ("User_Charlie", "User_Delta"),
    ("User_Delta", "User_Echo"),
    ("User_Echo", "User_Zulu"),
    ("User_Charlie", "User_Foxtrot"),
    ("User_Foxtrot", "User_Golf"),
    ("User_Golf", "User_Zulu"),
    ("User_Charlie", "User_Hotel"),
    ("User_Hotel", "User_Zulu"),
    ("User_India", "User_Juliet"),
    ("User_Kilo", "User_Lima"),
    ("User_Lima", "User_Mike"),
    ("User_Mike", "User_November"),
    ("User_November", "User_Oscar")
]

with open('/home/user/delegations.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["delegator", "delegatee", "timestamp"])
    for i, (u, v) in enumerate(edges):
        writer.writerow([u, v, f"2023-10-01T12:00:{i:02d}Z"])
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
