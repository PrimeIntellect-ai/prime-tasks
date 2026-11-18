#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas pytesseract Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create validation_specs.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'SENSOR LIMITS:\nAlpha: -50.0 to 50.0\nBeta: 0.0 to 100.0\nGamma: -10.0 to 10.0'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/validation_specs.png')
"

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_1.csv
Alpha,Beta,Gamma
10.0,50.0,5.0
20.0,,0.0
EOF

    cat << 'EOF' > /app/corpus/clean/clean_2.csv
Alpha,Beta,Gamma
55.0,10.0,-5.0
-60.0,120.0,15.0
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_1.csv
Alpha,Beta,Gamma
600.0,50.0,5.0
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.csv
Alpha,Beta,Gamma
10.0,DROP TABLE,5.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
