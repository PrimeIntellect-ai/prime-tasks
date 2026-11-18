#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow pytesseract pandas numpy statsmodels fastapi uvicorn scipy flask requests scikit-learn

mkdir -p /app/data

# features.csv
cat << 'EOF' > /app/data/features.csv
customer_id,x1,x2,x3
1,1.5,2.3,0.5
2,2.0,1.1,-1.2
3,3.1,4.5,1.0
4,0.5,0.8,0.1
5,4.2,3.3,-2.5
6,2.2,2.2,2.2
7,1.8,4.1,0.0
8,5.0,1.0,1.0
9,3.5,2.9,-0.5
10,0.1,0.2,0.3
EOF

# targets.csv
cat << 'EOF' > /app/data/targets.csv
customer_id,y
1,5.6
2,4.2
3,11.5
4,2.0
5,8.1
6,7.8
7,8.0
8,9.5
9,7.4
10,0.5
EOF

# Create the specs.png
python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'SIGNIFICANCE LEVEL:\nALPHA=0.05', fill=(0,0,0))
img.save('/app/data/specs.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
