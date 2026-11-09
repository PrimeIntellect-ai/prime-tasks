#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick rustc cargo fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate settings.png
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,40 'BLOCK_ID=ERR_77' text 10,80 'MAX_ROLLING_SUM=500' text 10,120 'WINDOW=3'" /app/settings.png

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
[
  {"id": 1, "val": 100, "tag": "INFO"},
  {"id": 2, "val": 150, "tag": "DEBUG"},
  {"id": 3, "val": 200, "tag": "WARN"}
]
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
[
  {"id": 4, "val": 50, "tag": "INFO"},
  {"id": 5, "val": 50, "tag": "INFO"},
  {"id": 6, "val": 50, "tag": "INFO"}
]
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
[
  {"id": 1, "val": 100, "tag": "INFO"},
  {"id": 2, "val": 150, "tag": "ERR_77"},
  {"id": 3, "val": 300, "tag": "WARN"},
  {"id": 4, "val": 200, "tag": "INFO"}
]
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
[
  {"id": 1, "val": 200, "tag": "INFO"},
  {"id": 2, "val": 250, "tag": "INFO"},
  {"id": 3, "val": 100, "tag": "ERR_77"},
  {"id": 4, "val": 100, "tag": "INFO"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
