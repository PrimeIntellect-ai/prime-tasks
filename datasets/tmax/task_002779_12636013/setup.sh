#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
id,name,metadata
1,Alice,"{""preferences"": {""theme"": ""dark""}}"
2,Bob,"{""preferences"": {""theme"": ""light""}}"
3,Charlie,"{""account_type"": ""guest""}"
4,Dave,"{""preferences"": {""theme"": ""dark""}}"
5,Eve,"{""preferences"": {}}"
EOF

    cat << 'EOF' > /home/user/processor.py
import csv
import json
import sys

def process_users(input_file, output_file):
    processed = []
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            metadata = json.loads(row['metadata'])
            # The bug is here: assumes 'preferences' and 'theme' always exist
            theme = metadata['preferences']['theme']

            processed.append({
                'id': row['id'],
                'name': row['name'],
                'theme': theme
            })

    with open(output_file, 'w') as f:
        json.dump(processed, f, indent=2)

if __name__ == "__main__":
    process_users('/home/user/data/users.csv', '/home/user/output.json')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
