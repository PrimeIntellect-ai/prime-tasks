#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate policy.png using Python and Pillow
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1000, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
text = "ATTENTION: Any record containing the exact project code format\nPROJ-XRAY-\d{4}-ZULU in the comments must be scrubbed\nfrom the system immediately."
d.text((10,10), text, fill=(0,0,0), font=font)
img.save('/app/policy.png')
EOF
    python3 /tmp/make_img.py

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/data.csv
transaction_id,user_id,timestamp,comments
1,U1,2023-01-01T10:00:00Z,  first comment  
2,U1,2023-01-01T11:00:00Z, second comment
3,U2,2023-01-02T10:00:00Z, normal text
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/data.csv
transaction_id,user_id,timestamp,comments
4,U3,2023-01-03T10:00:00Z, PROJ-XRAY-1234-ZULU secret
5,U4,2023-01-04T10:00:00Z, PROJ-XRAY-9999-ZULU
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
