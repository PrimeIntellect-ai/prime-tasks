#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Create dummy shared library
    cat << 'EOF' > /tmp/dummy.c
void dummy() {}
EOF
    gcc -shared -fPIC -o /app/libdata.so /tmp/dummy.c
    rm /tmp/dummy.c

    # Create legacy processor script
    cat << 'EOF' > /app/legacy_processor.py
import urllib2
import BaseHTTPServer
import ctypes

class DataStruct(ctypes.Structure):
    _fields_ = [("name", ctypes.c_char_p), ("value", ctypes.c_int)]

def process():
    lib = ctypes.CDLL('/app/libdata.so')
    # In python 2, strings were bytes. In python 3, this needs b"test"
    item = DataStruct("test", 42)
    print "Initialized struct"
EOF

    # Generate image with text
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Load Order:\n1. Auth v1.2.4\n2. Data v2.0.1\n3. Sink v0.9.4'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/legacy_specs.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
