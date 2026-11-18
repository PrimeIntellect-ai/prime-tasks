#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr git bc gawk file
    pip3 install pytest Pillow

    mkdir -p /app/log_repo /app/clean /app/evil

    # Create specs.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 40), 'MAX_SAFE_VALUE=32767.99', fill=(0, 0, 0))
img.save('/app/specs.png')
"

    # Populate clean directory
    for i in $(seq 1 50); do
        echo "150.5" > /app/clean/log_$i.txt
        echo "32767.98" >> /app/clean/log_$i.txt
    done

    # Populate evil directory
    for i in $(seq 1 25); do
        echo "32768.00" > /app/evil/log_$i.txt
    done
    for i in $(seq 26 50); do
        printf "\xff\xfe\x00\x00" > /app/evil/log_$i.txt
    done

    # Create log_repo with 200 commits
    cd /app/log_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    for i in $(seq 1 200); do
        echo "commit $i" > file.txt
        git add file.txt
        git commit -m "commit $i" > /dev/null
    done
    cd /

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
