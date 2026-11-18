#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import json
import csv

config = {
    "ref_lat": 48.8566,
    "ref_lon": 2.3522
}

with open('/home/user/config.json', 'w') as f:
    json.dump(config, f)

csv_data = [
    ["store_id", "name_native", "latitude", "longitude"],
    ["1", "Caf\u00e9 Paris", "48.858", "2.351"],
    ["2", "Cafe\u0301 Paris", "48.862", "2.349"],
    ["3", "M\u00fcnchen Store", "48.135", "11.582"],
    ["4", "\u6771\u4eac (Tokyo)", "35.680", "139.760"],
    ["5", "CAF\u00c9 PARIS", "48.859", "2.350"],
    ["6", "Boulangerie", "48.857", "2.353"]
]

with open('/home/user/raw_stores.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerows(csv_data)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
