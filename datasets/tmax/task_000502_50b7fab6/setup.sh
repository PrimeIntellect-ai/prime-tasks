#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate the config_spec.png image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Specs for Retry Filter:\nWINDOW_SIZE=120\nNORMALIZATION_PREFIX=cfg_'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/config_spec.png')
"

    # Generate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean_1.jsonl
{"id": "1", "host": "h1", "ts": 1000, "config_payload": "payload_A"}
{"id": "2", "host": "h1", "ts": 1200, "config_payload": "payload_B"}
{"id": "3", "host": "h2", "ts": 1050, "config_payload": "payload_A"}
{"id": "4", "host": "h1", "ts": 1400, "config_payload": "payload_A"}
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil_1.jsonl
{"id": "1", "host": "h1", "ts": 1000, "config_payload": "payload_A"}
{"id": "2", "host": "h1", "ts": 0, "config_payload": "PAYLOAD_A "}
{"id": "3", "host": "h1", "ts": 1100, "config_payload": "payload_B"}
{"id": "4", "host": "h2", "ts": 2000, "config_payload": "payload_C"}
{"id": "5", "host": "h2", "ts": 2050, "config_payload": "  PaYlOaD_C"}
{"id": "6", "host": "h2", "ts": 2200, "config_payload": "payload_D"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
