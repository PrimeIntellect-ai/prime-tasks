#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest scikit-learn Pillow

    mkdir -p /app/eval_clean /app/eval_evil

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''CONFIGURATION
THRESHOLD: 0.82
TEMPLATES:
1. Earn money fast working from home
2. Click the link to claim your prize
3. Buy cheap luxury watches today'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/config_spec.png')
"

    cat << 'EOF' > /app/eval_clean/review1.txt
This watch is fantastic, I wear it every day and it keeps perfect time.
EOF
    cat << 'EOF' > /app/eval_clean/review2.txt
The product arrived late but works as described.
EOF
    cat << 'EOF' > /app/eval_clean/review3.txt
I do not recommend this item, it broke after two uses.
EOF

    cat << 'EOF' > /app/eval_evil/spam1.txt
Earn money fast working from home now
EOF
    cat << 'EOF' > /app/eval_evil/spam2.txt
Please click the link to claim your prize today
EOF
    cat << 'EOF' > /app/eval_evil/spam3.txt
Buy cheap luxury watches today online
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
