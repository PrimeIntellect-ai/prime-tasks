#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /app/transform_matrix.csv
0.5,0.8
-0.2,0.1
EOF

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 150), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Column Type Nullable\npatient_id int False\nage int True\nweight float True'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/schema.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
