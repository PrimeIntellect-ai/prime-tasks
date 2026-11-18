#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/backups.json
[
  {"node": "A", "size_gb": 10},
  {"node": "B", "size_gb": 20},
  {"node": "C", "size_gb": 15},
  {"node": "D", "size_gb": 30},
  {"node": "E", "size_gb": 25}
]
EOF

    # Generate the topology image
    convert -font Liberation-Sans -pointsize 24 -background white -fill black label:"A -> B : 2\nA -> C : 4\nB -> D : 1\nC -> D : 5\nD -> E : 3" /app/topology.png

    # Create the verifier script
    cat << 'EOF' > /verify.py
import json
import sys

try:
    with open('/home/user/top_backups.json', 'r') as f:
        agent_data = json.load(f)
except Exception as e:
    print(f"Failed to load output: {e}")
    sys.exit(1)

expected = [
    {"node": "B", "score": 56.25},
    {"node": "D", "score": 38.333333333333336},
    {"node": "A", "score": 37.916666666666664},
    {"node": "E", "score": 25.0},
    {"node": "C", "score": 24.125}
]

if len(agent_data) != 5:
    print(f"Expected 5 items, got {len(agent_data)}")
    sys.exit(1)

max_error = 0.0
for i in range(5):
    if agent_data[i]["node"] != expected[i]["node"]:
        print(f"Node mismatch at index {i}: expected {expected[i]['node']}, got {agent_data[i].get('node')}")
        sys.exit(1)
    error = abs(agent_data[i]["score"] - expected[i]["score"])
    if error > max_error:
        max_error = error

print(f"MAE: {max_error}")
if max_error <= 0.1:
    sys.exit(0)
else:
    print("Error exceeds threshold.")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
