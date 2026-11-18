#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create the config_rules.png
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,40 'EXCLUDE_TYPE=SYSTEM' text 20,80 'MAX_WEIGHT=800' text 20,120 'MINIMUM_DEGREE=2'" /app/config_rules.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle.py
import sys
import json
from collections import defaultdict

def main():
    try:
        data = json.load(sys.stdin)
    except:
        print("[]")
        return

    exclude_type = "SYSTEM"
    max_weight = 800
    min_degree = 2

    nodes = defaultdict(lambda: {"degree": 0, "weight_sum": 0})

    for edge in data:
        if edge.get("type") == exclude_type:
            continue
        weight = edge.get("weight", 0)
        if weight > max_weight:
            continue

        src = edge["src"]
        dst = edge["dst"]

        nodes[src]["degree"] += 1
        nodes[src]["weight_sum"] += weight

        nodes[dst]["degree"] += 1
        nodes[dst]["weight_sum"] += weight

    result = []
    for node_id, stats in nodes.items():
        if stats["degree"] >= min_degree:
            result.append({
                "node": node_id,
                "degree": stats["degree"],
                "weight_sum": stats["weight_sum"]
            })

    result.sort(key=lambda x: (-x["degree"], x["node"]))
    print(json.dumps(result))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
