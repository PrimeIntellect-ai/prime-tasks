#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential tesseract-ocr
    pip3 install pytest pytesseract Pillow hypothesis packaging

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'v1.4.2', fill=(0, 0, 0))
img.save('/app/requirements.png')
"

    mkdir -p /home/user/math_optimizer

    cat << 'EOF' > /home/user/math_optimizer/mathops.c
#include <math.h>
#include <stdlib.h>

const char* get_version() {
    return "1.5.0";
}

void matrix_transform(double* matrix) {
    for(int i=0; i<9; i++) {
        matrix[i] = sin(matrix[i]) * cos(matrix[i]) + exp(-matrix[i]);
    }
}
EOF

    cat << 'EOF' > /home/user/math_optimizer/Makefile
all: libmathops.so

libmathops.so: mathops.c
	gcc mathops.c -o libmathops.so
EOF

    cat << 'EOF' > /home/user/math_optimizer/test_ops.py
import ctypes
import os
from hypothesis import given, strategies as st

# Load libmathops.so
# Extract version
# Compare version with image from /app/requirements.png

@given(st.lists(st.floats(min_value=-10, max_value=10), min_size=9, max_size=9))
def test_matrix_transform(matrix):
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
