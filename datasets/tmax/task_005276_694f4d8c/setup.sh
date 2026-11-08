#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr jq
    pip3 install pytest Pillow

    mkdir -p /app/clean_corpus /app/evil_corpus

    cat << 'EOF' > /app/clean_corpus/clean1.jsonl
{"parent_id": 10, "child_parent_id": 10, "parent_region": "NA", "child_region": "NA", "status": "ACTIVE", "data": "foo"}
{"parent_id": 20, "child_parent_id": 20, "parent_region": "EU", "child_region": "EU", "status": "ACTIVE", "data": "bar"}
EOF

    cat << 'EOF' > /app/evil_corpus/evil1.jsonl
{"parent_id": 10, "child_parent_id": 20, "parent_region": "NA", "child_region": "NA", "status": "ACTIVE", "data": "foo"}
{"parent_id": 10, "child_parent_id": 10, "parent_region": "NA", "child_region": "EU", "status": "ACTIVE", "data": "foo"}
{"parent_id": 10, "child_parent_id": 10, "parent_region": "NA", "child_region": "NA", "status": "INACTIVE", "data": "foo"}
EOF

    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "VALIDATION RULES:\n1. The field 'parent_id' must exactly match 'child_parent_id'.\n2. The field 'parent_region' must exactly match 'child_region'.\n3. The field 'status' must be exactly 'ACTIVE'."
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/schema_rules.png')
EOF
    python3 /tmp/make_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
