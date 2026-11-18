#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        fonts-liberation \
        make

    pip3 install pytest hypothesis Pillow pytesseract

    mkdir -p /app/corpus/clean /app/corpus/evil /app/eval_corpus/clean /app/eval_corpus/evil

    echo "Hello world" > /app/corpus/clean/1.txt
    echo "Just some normal text" > /app/corpus/clean/2.txt

    echo "AKIA1234567890ABCDEF" > /app/corpus/evil/1.txt
    echo "Traceback (most recent call last):" > /app/corpus/evil/2.txt
    echo "<html><body>Hi</body></html>" > /app/corpus/evil/3.txt
    echo "Server at 10.1.2.3" > /app/corpus/evil/4.txt

    echo "Another clean text" > /app/eval_corpus/clean/1.txt
    echo "AKIAABCDEFGHIJKLMNOP" > /app/eval_corpus/evil/1.txt
    echo "Exception: something went wrong" > /app/eval_corpus/evil/2.txt
    echo "<div>hello</div>" > /app/eval_corpus/evil/3.txt
    echo "Ping 192.168.10.10" > /app/eval_corpus/evil/4.txt

    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Dashboard View\nWelcome test user!\nException in thread main\nConnection to 192.168.1.100 failed"
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
except Exception:
    font = ImageFont.load_default()
d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/screenshot.png')
EOF
    python3 /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
