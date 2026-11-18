#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Create schema image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 16 -fill black -annotate +10+20 "ALLOWED EDGES:\nUser-[Bought]->Product\nUser-[Follows]->User\nProduct-[SimilarTo]->Product\nMAX DEPTH: 3 edges" /app/schema.png

    # Create clean corpus
    cat << 'EOF' > /app/clean/queries.jsonl
{"id": "c1", "path": ["User"]}
{"id": "c2", "path": ["User", "Bought", "Product"]}
{"id": "c3", "path": ["User", "Follows", "User", "Bought", "Product"]}
{"id": "c4", "path": ["User", "Bought", "Product", "SimilarTo", "Product", "SimilarTo", "Product"]}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/evil/queries.jsonl
{"id": "e1", "path": ["User", "Bought", "User"]}
{"id": "e2", "path": ["Product", "Bought", "User"]}
{"id": "e3", "path": ["User", "Follows", "User", "Follows", "User", "Follows", "User", "Follows", "User"]}
{"id": "e4", "path": ["User", "Bought"]}
{"id": "e5", "path": []}
{"id": "e6", "path": ["User", "Follows", "Product"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
