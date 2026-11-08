#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core tesseract-ocr tesseract-ocr-eng
    pip3 install pytest

    # Remove ImageMagick policy to allow drawing and saving images
    rm -f /etc/ImageMagick-6/policy.xml

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'MAX_ALLOWED_LOSS=0.0004'" /app/threshold.png

    mkdir -p /tmp/clean_corpus /tmp/evil_corpus

    cat << 'EOF' > /tmp/clean_corpus/clean1.log
{"service": "settlement", "tx_id": "tx-1", "final_amount": 100.1234}
{"service": "processor", "tx_id": "tx-1", "status": "processing"}
{"service": "gateway", "tx_id": "tx-1", "amount": "100.12345"}
EOF

    cat << 'EOF' > /tmp/clean_corpus/clean2.log
{"service": "processor", "tx_id": "tx-2", "status": "processing"}
{"service": "gateway", "tx_id": "tx-2", "amount": "50.0004"}
{"service": "settlement", "tx_id": "tx-2", "final_amount": 50.0000}
EOF

    cat << 'EOF' > /tmp/evil_corpus/evil1.log
{"service": "gateway", "tx_id": "tx-3", "amount": "100.12345"}
{"service": "settlement", "tx_id": "tx-3", "final_amount": 100.1220}
{"service": "processor", "tx_id": "tx-3", "status": "processing"}
EOF

    cat << 'EOF' > /tmp/evil_corpus/evil2.log
{"service": "settlement", "tx_id": "tx-4", "final_amount": 99.9990}
{"service": "gateway", "tx_id": "tx-4", "amount": "99.9999"}
{"service": "processor", "tx_id": "tx-4", "status": "processing"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
