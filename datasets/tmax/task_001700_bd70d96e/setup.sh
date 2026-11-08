#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    ['timestamp', 'user_id', 'review_text', 'rating'],
    ['2023-01-15T10:00:00Z', 'u1', 'Great product!\nReally loved it.', '5'],
    ['2023-01-15T09:00:00Z', 'u1', 'Older review', '4'],
    ['2023-01-16T11:00:00Z', 'u2', 'C\'est bon', '4'],
    ['2023-02-14T15:00:00Z', 'u4', 'cafe\u0301', '3'],
    ['2023-02-10T12:00:00Z', 'u3', 'No rating', ''],
    ['2023-02-15T15:00:00Z', 'u5', 'Broken \n\n CSV', '2'],
    ['2023-03-01T08:00:00Z', 'u6', '\u3053\u3093\u306b\u3061\u306f', '5'],
    ['2023-03-05T09:00:00Z', 'u6', 'Updated \r\n review \n text', '4']
]

with open('/home/user/raw_reviews.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
