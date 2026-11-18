#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cd /home/user/project
    git init

    # Create the python script
    cat << 'EOF' > parse_config.py
import json
import sys

def process_config(file_path):
    with open(file_path, 'r') as f:
        data = json.load(f)

    total_weight = 0
    for item in data:
        # Vulnerable to missing or string 'weight'
        total_weight += item['weight']

    print(f"Total weight: {total_weight}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse_config.py <file>")
        sys.exit(1)
    process_config(sys.argv[1])
EOF

    # Create the corrupted JSON file
    cat << 'EOF' > bad_config.json
[
  {"id": 1, "weight": 10},
  {"id": 2, "weight": "corrupted_value"},
  {"id": 3, "weight": 5}
]
EOF

    # Stage the file to create a blob, then delete it
    git add bad_config.json
    git rm -f --cached bad_config.json
    rm bad_config.json

    # Create the log file simulating the crash
    cat << 'EOF' > build.log
[INFO] Starting build pipeline...
[INFO] Running parse_config.py on bad_config.json
Traceback (most recent call last):
  File "parse_config.py", line 18, in <module>
    process_config(sys.argv[1])
  File "parse_config.py", line 11, in process_config
    total_weight += item['weight']
TypeError: unsupported operand type(s) for +=: 'int' and 'str'
[ERROR] Build failed with exit code 1.
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
