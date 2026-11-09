#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /home/user/corpus/clean /home/user/corpus/evil /app

    # Create image fixture
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,30 'VALID MAGIC: 0x4B 0x4F 0x4E 0x46'" -draw "text 10,70 'EVIL SIGNATURE: 0x62 0x61 0x64 0x63 0x6F 0x6E 0x66'" /app/schema.png

    # Create clean corpus
    echo -n "KONF" > /home/user/corpus/clean/cfg1.bin
    echo -n "user=admin;pass=123" >> /home/user/corpus/clean/cfg1.bin

    echo -n "KONF" > /home/user/corpus/clean/cfg2.bin
    echo -n "host=localhost;port=8080" >> /home/user/corpus/clean/cfg2.bin

    # Create evil corpus
    echo -n "KONF" > /home/user/corpus/evil/evil1.bin
    echo -n "user=admin;badconf;pass=123" >> /home/user/corpus/evil/evil1.bin

    echo -n "BAD!" > /home/user/corpus/evil/evil2.bin
    echo -n "user=admin;pass=123" >> /home/user/corpus/evil/evil2.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
