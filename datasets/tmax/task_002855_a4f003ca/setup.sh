#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (2000, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "CRITICAL DEADLOCK AVOIDANCE RULE: Any NoSQL aggregation pipeline that ends with a $merge into the 'ledger' collection MUST satisfy two conditions to avoid deadlocking concurrent transactions: 1) It must have a $match stage that filters by 'tenant_id' before the merge. 2) It must have a $sort stage on 'transaction_date' descending (i.e., {\"transaction_date\": -1}) before the merge to align with the { tenant_id: 1, transaction_date: -1 } compound index."
d.text((10,10), text, fill=(0,0,0))
img.save('/app/db_schema_notes.png')
EOF
    python3 /tmp/make_image.py

    echo '[{"$merge": {"into": "ledger"}}]' > /app/corpus/evil/evil_1.json
    echo '[{"$match": {"tenant_id": 123}}, {"$sort": {"transaction_date": -1}}, {"$merge": {"into": "ledger"}}]' > /app/corpus/clean/clean_1.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
