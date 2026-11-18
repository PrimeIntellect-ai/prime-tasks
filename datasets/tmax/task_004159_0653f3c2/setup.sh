#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas python-dateutil

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv

data = [
    {"id": "1", "email": "alice.wonder@uk.com", "timestamp": "2023-01-15 14:30:00", "metadata": r'{"name": "alice WONDER", "age": 25, "country": "UK"}', "feedback": "Great service! Call me at 123-456-7890."},
    {"id": "2", "email": "bob.builder@com.com", "timestamp": "02/14/2023 09:15:00", "metadata": r'{"name": "BOB b", "age": null, "country": ""}', "feedback": "The item was broken. My number is 0987654321, please call."},
    {"id": "3", "email": "charlie@ca.com", "timestamp": "March 3, 2023 18:00:00", "metadata": r'{"name": "charlie \u263A", "age": 40, "country": "CA"}', "feedback": "Nice."},
    {"id": "4", "email": "dave.danger@com.com", "timestamp": "2023-04-10T11:11:11", "metadata": r'{"name": "dav\uX9e danger", "age": 30, "country": "US"}', "feedback": "Call 111-222-3333 or 4445556666."},
    {"id": "5", "email": "eve.evil@uk.com", "timestamp": "2023-05-05 12:00:00", "metadata": r'{"name": " eve ", "age": null, "country": null}', "feedback": "No phone here."}
]

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["id", "email", "timestamp", "metadata", "feedback"])
    writer.writeheader()
    for row in data:
        writer.writerow(row)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
