#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-dejavu-core
    pip3 install pytest pytesseract opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /tmp/users.txt
UID | USERNAME | DEPARTMENT
001 | ALICE | ENGINEERING
002 | BOB | MARKETING
003 | CHARLIE | SALES
004 | DIANA | ENGINEERING
005 | EVE | HUMAN_RESOURCES
006 | FRANK | ENGINEERING
007 | GRACE | SALES
008 | HEIDI | MARKETING
009 | IVAN | ENGINEERING
010 | JUDY | SALES
EOF

    ffmpeg -f lavfi -i color=c=black:s=640x480:d=15 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/users.txt:fontcolor=white:fontsize=24:x=(w-text_w)/2:y=h-t*40" \
        -c:v libx264 -y /app/legacy_user_db.mp4

    rm /tmp/users.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
