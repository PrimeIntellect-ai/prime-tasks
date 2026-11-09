#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate image using Python and PIL
cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
import os

text = """GRAPH SCHEMA V2
Allowed Edges:
User -> PURCHASES -> Product
User -> REVIEWS -> Product
Product -> BELONGS_TO -> Category
Mandatory Constraints:
- source.label, relationship, and target.label must match the Allowed Edges exactly.
- target.id must be a scalar string. No wildcards (*) or arrays permitted."""

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/graph_schema.png')
EOF
python3 /tmp/gen_image.py

# Create clean corpus
cat << 'EOF' > /app/corpus/clean/c1.json
{"source": {"label": "User", "id": "u1"}, "relationship": "PURCHASES", "target": {"label": "Product", "id": "p1"}}
EOF
cat << 'EOF' > /app/corpus/clean/c2.json
{"source": {"label": "User", "id": "u2"}, "relationship": "REVIEWS", "target": {"label": "Product", "id": "p2"}}
EOF
cat << 'EOF' > /app/corpus/clean/c3.json
{"source": {"label": "Product", "id": "p1"}, "relationship": "BELONGS_TO", "target": {"label": "Category", "id": "c1"}}
EOF
for i in $(seq 4 10); do
    cp /app/corpus/clean/c1.json /app/corpus/clean/c${i}.json
done

# Create evil corpus
cat << 'EOF' > /app/corpus/evil/e1.json
{"source": {"label": "User", "id": "u1"}, "relationship": "PURCHASES", "target": {"label": "Product", "id": "*"}}
EOF
cat << 'EOF' > /app/corpus/evil/e2.json
{"source": {"label": "User", "id": "u1"}, "relationship": "PURCHASES", "target": {"label": "Product", "id": ["p1", "p2"]}}
EOF
cat << 'EOF' > /app/corpus/evil/e3.json
{"source": {"label": "User", "id": "u1"}, "relationship": "LIKES", "target": {"label": "Product", "id": "p1"}}
EOF
cat << 'EOF' > /app/corpus/evil/e4.json
{"source": {"label": "Product", "id": "p1"}, "relationship": "PURCHASES", "target": {"label": "User", "id": "u1"}}
EOF
for i in $(seq 5 10); do
    cp /app/corpus/evil/e1.json /app/corpus/evil/e${i}.json
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
