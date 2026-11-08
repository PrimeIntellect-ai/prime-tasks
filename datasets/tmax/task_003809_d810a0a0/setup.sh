#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y ffmpeg tesseract-ocr fonts-dejavu-core xxd

    # Create directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create Evil corpus
    for i in 1 2 3 4 5; do
        echo "Log entry: SBX_SECRET_$(head -c 8 /dev/urandom | xxd -p)" > /app/corpus/evil/secret_$i.txt
        echo "Dump: 7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00" > /app/corpus/evil/elf_$i.txt
    done

    # Create Clean corpus
    for i in 1 2 3 4 5; do
        echo "Log entry: SBX_SECRET_REDACTED" > /app/corpus/clean/log_$i.txt
        echo "Dump: 89 50 4e 47 0d 0a 1a 0a 00 00 00 0d 49 48 44 52" > /app/corpus/clean/png_$i.txt
    done

    # Generate video
    # 142 frames at 30fps is ~4.73 seconds.
    ffmpeg -f lavfi -i color=c=black:s=640x480:r=30:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='EXPLOIT_SUCCESS':fontcolor=white:fontsize=24:x=10:y=10:enable='gte(n\,142)'" -c:v libx264 /app/sandbox_review.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
