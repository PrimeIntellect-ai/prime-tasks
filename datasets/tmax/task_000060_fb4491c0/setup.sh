#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        cargo \
        rustc \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the auditor certificate image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'SEC-AUDIT-AUTH-7734'" /app/auditor_cert.png

    # Generate hex-encoded payloads
    python3 -c "
import os, binascii

def make_payload(filename, content_str):
    elf_header = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    payload = elf_header + content_str.encode('utf-8')
    with open(filename, 'w') as f:
        f.write(binascii.hexlify(payload).decode('utf-8'))

# Clean payloads
make_payload('/app/corpus/clean/1.txt', 'some random data SEC-AUDIT-AUTH-7734 more data')
make_payload('/app/corpus/clean/2.txt', 'SEC-AUDIT-AUTH-7734 only')

# Evil payloads
make_payload('/app/corpus/evil/1.txt', 'missing token here')
make_payload('/app/corpus/evil/2.txt', 'SEC-AUDIT-AUTH-7734 but has UNION SELECT')
make_payload('/app/corpus/evil/3.txt', 'SEC-AUDIT-AUTH-7734 and javascript:alert(1)')
make_payload('/app/corpus/evil/4.txt', 'SEC-AUDIT-AUTH-7734 onerror=')
make_payload('/app/corpus/evil/5.txt', \"SEC-AUDIT-AUTH-7734 ' OR '1'='1\")
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
