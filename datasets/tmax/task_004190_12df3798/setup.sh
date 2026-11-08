#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y imagemagick tesseract-ocr libssl-dev fonts-dejavu-core gcc make

    mkdir -p /app/data/dirA /app/data/dirB
    echo "hello world" > /app/data/file1.txt
    echo "secret data" > /app/data/dirA/file2.txt
    echo "more data" > /app/data/dirB/file3.txt

    # Create symlink loop
    ln -s /app/data/dirB /app/data/dirA/link_to_B
    ln -s /app/data/dirA /app/data/dirB/link_to_A

    # Create the policy image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
    -draw "text 10,30 'BACKUP POLICY v2.1'" \
    -draw "text 10,60 'Target Directory: /app/data'" \
    -draw "text 10,90 'Output Manifest: /home/user/manifest.txt'" \
    -draw "text 10,120 'Hash Algorithm: MD5'" \
    /app/policy.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
