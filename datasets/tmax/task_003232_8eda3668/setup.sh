#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    cat << 'EOF' > /tmp/setup.py
import os
import json
from PIL import Image, ImageDraw

# 1. Create the image fixture
os.makedirs("/app", exist_ok=True)
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "DATABASE OPERATION COSTS\nINDEX_SCAN: 10\nTABLE_SCAN: 50\nHASH_JOIN: 20\nNESTED_LOOP: 100\nGRAPH_TRAVERSAL: 5"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/plan_costs.png')

# 2. Create the oracle
os.makedirs("/opt", exist_ok=True)
oracle_code = """import sys, json

COSTS = {
    "INDEX_SCAN": 10,
    "TABLE_SCAN": 50,
    "HASH_JOIN": 20,
    "NESTED_LOOP": 100,
    "GRAPH_TRAVERSAL": 5
}

def calc_cost(node):
    if not isinstance(node, dict): return 0
    cost = COSTS.get(node.get("operation", ""), 0)
    if "left" in node: cost += calc_cost(node["left"])
    if "right" in node: cost += calc_cost(node["right"])
    if "children" in node and isinstance(node["children"], list):
        for child in node["children"]:
            cost += calc_cost(child)
    return cost

if __name__ == "__main__":
    try:
        data = json.loads(sys.stdin.read())
        print(calc_cost(data))
    except Exception as e:
        print(0)
"""
with open('/opt/oracle_evaluator.py', 'w') as f:
    f.write(oracle_code)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
