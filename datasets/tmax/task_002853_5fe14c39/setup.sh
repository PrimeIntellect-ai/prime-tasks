#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app/legacy_calc

    cat << 'EOF' > /app/legacy_calc/matrix_ops.h
double compute_calibrated(double input, double coeff);
EOF

    cat << 'EOF' > /app/legacy_calc/matrix_ops.c
#include "matrix_ops.h"
double compute_calibrated(double input, double coeff) {
    return (input * coeff) + 100.0;
}
EOF

    cat << 'EOF' > /app/legacy_calc/Makefile
CC=gcc
CFLAGS=-Wall

all: libmatrix_ops.so

libmatrix_ops.so: matrix_ops.c
    $(CC) $(CFLAGS) -shared -o libmatrix_ops.so matrix_ops.c
EOF

    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
except:
    font = ImageFont.load_default()
text = "SYSTEM CONFIGURATION PARAMETERS\n-------------------------------\nACCESS_TOKEN : K83-F9A-X7M\nBASE_MULTIPLIER : 3.14159\n"
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/calibration.png')
EOF
    python3 /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
