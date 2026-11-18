#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow lxml

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the setup script
    cat << 'EOF' > /tmp/setup.py
import os
import csv
import json
import xml.etree.ElementTree as ET

os.makedirs('/home/user/raw_data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

# Data definition
# user_id, timestamp, message
data = [
    # User 1: 2 duplicates removed
    (1, 1600000000, "Hello World!"), # CSV
    (1, 1600000010, "hello world!"), # CSV - duplicate
    (1, 1600000020, "HELLO WORLD!"), # JSONL - duplicate

    # User 2: 1 duplicate removed (Unicode testing)
    (2, 1600000005, "Café"), # JSONL
    (2, 1600000015, "Cafe\u0301"), # XML - duplicate (NFD form of Café)

    # User 3: 3 duplicates removed
    (3, 1600000000, "こんにちは"), # XML
    (3, 1600000001, "こんにちは"), # XML - duplicate
    (3, 1600000002, "こんにちは"), # XML - duplicate
    (3, 1600000003, "こんにちは"), # CSV - duplicate

    # User 4: no duplicates
    (4, 1600000000, "Unique message"), # CSV
]

csv_data = [data[0], data[1], data[8], data[9]]
jsonl_data = [data[2], data[3]]
xml_data = [data[4], data[5], data[6], data[7]]

with open('/home/user/raw_data/data.csv', 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'timestamp', 'message'])
    for row in csv_data:
        writer.writerow(row)

with open('/home/user/raw_data/data.jsonl', 'w', encoding='utf-8') as f:
    for row in jsonl_data:
        f.write(json.dumps({'uid': row[0], 'ts': row[1], 'msg': row[2]}) + '\n')

root = ET.Element("records")
for row in xml_data:
    rec = ET.SubElement(root, "record")
    ET.SubElement(rec, "id").text = str(row[0])
    ET.SubElement(rec, "time").text = str(row[1])
    ET.SubElement(rec, "text").text = row[2]

tree = ET.ElementTree(root)
tree.write('/home/user/raw_data/data.xml', encoding='utf-8', xml_declaration=True)
EOF

    # Run the setup script
    python3 /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
