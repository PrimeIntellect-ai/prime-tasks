#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transformer.py
import sys
import json

def process():
    batch = []
    for line_num, line in enumerate(sys.stdin, 1):
        line = line.strip()
        if not line: continue
        try:
            data = json.loads(line)
            if "id" not in data:
                raise ValueError("Missing ID")
            data['status'] = 'processed'
            batch.append(data)
        except json.JSONDecodeError:
            # Corrupted input handling bug: clears the whole batch!
            batch.append({"error": "corrupted"})
            batch = [] # BUG: Drops previously processed valid records
        except ValueError:
            continue

    for item in batch:
        print(json.dumps(item))

if __name__ == "__main__":
    process()
EOF

    chmod +x /home/user/transformer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
