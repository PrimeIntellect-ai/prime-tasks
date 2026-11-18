#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    # Create directories
    mkdir -p /app/data/relational
    mkdir -p /app/data/document
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate Image fixture
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'ROOT_NODE=ALPHA_01', fill=(0,0,0))
d.text((10,50), 'MAPPING=source_id->dest_id:weight', fill=(0,0,0))
img.save('/app/legacy_schema.png')
"

    # Generate Relational Data
    cat << 'EOF' > /app/data/relational/data.csv
source_id,dest_id,weight
ALPHA_01,BETA_04,1
BETA_04,GAMMA_02,1
EOF

    # Generate Document Data
    cat << 'EOF' > /app/data/document/data.json
[
  {"source_id": "GAMMA_02", "dest_id": "NODE_OMEGA", "weight": 1}
]
EOF

    # Generate Clean Corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
[
  {"source_id": "A", "dest_id": "B", "weight": 1}
]
EOF

    # Generate Evil Corpus
    cat << 'EOF' > /app/corpora/evil/evil1.json
[
  {"source_id": "A", "dest_id": "A", "weight": -1, "tag": "__malicious_loop__"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
