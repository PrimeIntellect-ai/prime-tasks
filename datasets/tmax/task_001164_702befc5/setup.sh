#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu
    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'SYSTEM BOOT SEQUENCE\nAUTH_TOKEN: SecretGraph77\nENV: PRODUCTION'" /app/config.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.jsonl
{"sender": "N1", "receiver": "N2", "amount": 100.0}
{"sender": "N2", "receiver": "N3", "amount": 200.0}
{"sender": "N3", "receiver": "N1", "amount": 50.0}
{"sender": "N1", "receiver": "N2", "amount": 50.0}
{"sender": "X1", "receiver": "Y1", "amount": 1000.0}
{"sender": "Y1", "receiver": "Z1", "amount": 500.0}
EOF

    chmod -R 777 /home/user
