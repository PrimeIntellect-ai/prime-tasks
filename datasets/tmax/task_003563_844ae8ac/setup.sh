#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Create the Python script to generate the image
    cat << 'EOF' > /tmp/generate_image.py
from PIL import Image, ImageDraw, ImageFont

text = """USER_ID DEPT LEVEL
201 ENG 5
202 HR 2
203 MKT 3
204 IT 9
205 ENG 4
206 FIN 6
207 SALES 3
208 RND 8"""

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 20)
except Exception:
    font = ImageFont.load_default()

# Create image with white background
img = Image.new('RGB', (400, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)

# Draw text
d.text((20, 20), text, fill=(0, 0, 0), font=font)

# Save image
img.save('/app/user_matrix.png')
EOF

    python3 /tmp/generate_image.py

    # Create expected output
    cat << 'EOF' > /tmp/expected_config.txt
alias: user201@eng.domain.com
route: 10.5.0.201
alias: user202@hr.domain.com
route: 10.2.0.202
alias: user203@mkt.domain.com
route: 10.3.0.203
alias: user204@it.domain.com
route: 10.9.0.204
alias: user205@eng.domain.com
route: 10.4.0.205
alias: user206@fin.domain.com
route: 10.6.0.206
alias: user207@sales.domain.com
route: 10.3.0.207
alias: user208@rnd.domain.com
route: 10.8.0.208
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
