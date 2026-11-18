#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick jq
    pip3 install pytest flask requests

    mkdir -p /home/user/data
    mkdir -p /app

    cat << 'EOF' > /home/user/data/papers.jsonl
{"paper_id": "P-1", "authors": ["A-100", "A-200"]}
{"paper_id": "P-2", "authors": ["A-842", "A-311", "A-412"]}
{"paper_id": "P-3", "authors": ["A-500", "A-842"]}
{"paper_id": "P-4", "authors": ["A-311", "A-999"]}
{"paper_id": "P-5", "authors": ["A-842", "A-412", "A-701"]}
EOF

    convert -size 400x100 xc:white -pointsize 24 -fill black -gravity center -annotate +0+0 'Target Author: A-842' /app/whiteboard.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
