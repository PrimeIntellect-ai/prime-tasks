#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import json

data = [
    {"id": "ds01", "domain": "genomics", "dependencies": ["ds02", "ds03", "ds04"]},
    {"id": "ds02", "domain": "genomics", "dependencies": ["ds03"]},
    {"id": "ds03", "domain": "genomics", "dependencies": ["ds01", "ds02"]},
    {"id": "ds04", "domain": "physics", "dependencies": ["ds01", "ds05"]},
    {"id": "ds05", "domain": "physics", "dependencies": ["ds06", "ds07", "ds08", "ds09"]},
    {"id": "ds06", "domain": "physics", "dependencies": ["ds05"]},
    {"id": "ds07", "domain": "physics", "dependencies": []},
    {"id": "ds08", "domain": "astronomy", "dependencies": ["ds09", "ds10"]},
    {"id": "ds09", "domain": "astronomy", "dependencies": ["ds08", "ds10"]},
    {"id": "ds10", "domain": "astronomy", "dependencies": ["ds08", "ds09"]}
]

with open('/home/user/datasets.jsonl', 'w') as f:
    for item in data:
        f.write(json.dumps(item) + '\n')
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
