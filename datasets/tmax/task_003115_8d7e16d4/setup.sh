#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app

    # Create the CSV file
    cat <<EOF > /app/mutations.csv
score
1.2
1.5
1.3
1.7
1.1
1.9
1.4
1.6
1.8
1.5
EOF

    # Create the image file
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 20), 'AUTH_TOKEN: BIO-77X9\nALPHA: 1.5\nBETA: 2.0', fill=(0, 0, 0))
img.save('/app/gel_metadata.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
