#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/telemetry_processor
cd /home/user/telemetry_processor

cat << 'EOF' > requirements.txt
pandas==2.0.3
numpy==1.20.0
EOF

cat << 'EOF' > data.json
[
  {
    "id": "e1",
    "value": 10,
    "next": {
      "id": "e2",
      "value": 20,
      "next": {
        "id": "e1",
        "value": 10
      }
    }
  },
  {
    "id": "e3",
    "value": 30,
    "next": {
      "id": "e4",
      "value": 40,
      "next": null
    }
  },
  {
    "id": "e5",
    "value": 50,
    "next": {
      "value": 60,
      "next": null
    }
  }
]
EOF

cat << 'EOF' > process.py
import json
import sys
import pandas as pd

def flatten_events(node, result):
    if not node:
        return

    # Bug 2: Missing 'id' key on e5's next node causes KeyError
    # Bug 1: No cycle detection (e1 -> e2 -> e1 causes infinite recursion)
    node_id = node['id']
    result.append({
        'id': node_id,
        'value': node.get('value', 0)
    })

    if 'next' in node and node['next']:
        flatten_events(node['next'], result)

def main():
    with open('data.json', 'r') as f:
        data = json.load(f)

    all_events = []

    for graph in data:
        flatten_events(graph, all_events)

    df = pd.DataFrame(all_events)
    summary = {
        "total_events_processed": len(df),
        "unique_event_ids": int(df['id'].nunique()),
        "total_value": int(df['value'].sum())
    }

    with open('summary.json', 'w') as f:
        json.dump(summary, f, indent=4)

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
