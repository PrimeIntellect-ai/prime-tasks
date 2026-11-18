#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        zip \
        unzip \
        tar \
        coreutils

    pip3 install pytest Pillow

    # Create directories
    mkdir -p /app/legacy_data
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user/processed_backup

    # Generate policy.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''CONFIDENTIAL MEMO
1. Legacy System Encoding: iso-8859-15
2. Mandatory File Prefix: BKP_2024_
3. Security Directive: Reject any file containing the exact string '[MALWARE-SIGNATURE-8821]'.'''
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/policy.png')
"

    # Generate corpora for verification
    for i in $(seq 1 50); do
        echo "This is a clean file with random content $i." > /app/corpora/clean/file_$i.txt
        echo "This is an evil file $i containing [MALWARE-SIGNATURE-8821] somewhere." > /app/corpora/evil/file_$i.txt
    done

    # Generate legacy data
    mkdir -p /tmp/legacy_raw
    python3 -c "
import os
def write_legacy(filename, content):
    with open(os.path.join('/tmp/legacy_raw', filename), 'wb') as f:
        f.write(content.encode('iso-8859-15'))

write_legacy('clean file 1.txt', 'Clean content 1')
write_legacy('clean file 2.txt', 'Clean content 2')
write_legacy('evil file 1.txt', 'Evil content [MALWARE-SIGNATURE-8821] here')
"

    cd /tmp/legacy_raw
    tar -cvf /tmp/nested.tar *
    cd /tmp
    zip archive.zip nested.tar

    # Split the zip archive into parts .001, .002, etc.
    python3 -c "
import os
with open('/tmp/archive.zip', 'rb') as f:
    data = f.read()
chunk_size = 1024
for i in range(0, len(data), chunk_size):
    idx = i // chunk_size + 1
    with open(f'/app/legacy_data/archive.zip.{idx:03d}', 'wb') as out:
        out.write(data[i:i+chunk_size])
"

    # Cleanup tmp
    rm -rf /tmp/legacy_raw /tmp/nested.tar /tmp/archive.zip

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
