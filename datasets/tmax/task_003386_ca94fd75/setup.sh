#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr

    pip3 install pytest pytesseract Pillow pandas flask fastapi uvicorn requests

    mkdir -p /home/user/data /app

    cat << 'EOF' > /home/user/data/records.csv
id,trials,successes,source_id
1,100,20,A
2,50,5,B
EOF

    cat << 'EOF' > /home/user/data/reference.json
{
  "A": {"alpha": 2, "beta": 8},
  "B": {"alpha": 1, "beta": 9}
}
EOF

    # Remove ImageMagick security policy restrictions for this generation if needed
    sed -i 's/<policy domain="coder" rights="none" pattern="PDF" \/>/<!-- <policy domain="coder" rights="none" pattern="PDF" \/> -->/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 10,30 'API Specifications:' text 10,60 'Port: 8123' text 10,90 'Endpoint: /api/v1/posterior' text 10,120 'Auth Token: Bearer bayes_rule_2024' text 10,150 'Response format: {\"id\": <int>, \"posterior_mean\": <float>}'" \
        /app/api_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
