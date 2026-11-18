#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    ("001", "2023-10-15T14:30:00Z", "IP: 192.168.1.1 | Region: EU | browser: chrome", "Привет [RATING: 5]"),
    ("002", "2023-10-15 14:30:00", "IP: 10.0.0.1 | Region: NA", "Good [RATING: 4]"),
    ("003", "2023-10-16T09:15:00Z", "Some garbage here. Region: NA. User IP: 10.0.0.1.", "Excellent [RATING:4] 漢字"),
    ("004", "2023-10-17T11:00:00Z", "IP: 256.0.0.1 | Region: EU", "Bad [RATING: 1]"),
    ("005", "2023-10-18T18:45:00Z", "IP: 172.16.0.5 | Region: EU", "Trés bien [RATING: 2]"),
    ("006", "2023-10-19T12:00:00Z", "IP: 8.8.8.8 | Region: AS", "No rating given here"),
    ("007", "2023-10-19T13:00:00Z", "IP: 8.8.8.8 | Region: AS", "Fake rating [RATING: 6]"),
    ("008", "2023-10-20T08:00:00Z", "Just IP: 1.1.1.1 here", "Bad 😭 [RATING: 1]")
]

with open('/home/user/raw_feedback.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(["id", "timestamp", "user_metadata", "feedback_text"])
    writer.writerows(data)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
