#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gcc \
        fonts-dejavu \
        libtesseract-dev

    pip3 install pytest Pillow numpy requests

    mkdir -p /app
    mkdir -p /home/user

    # Create the kernel image using Python and Pillow
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('L', (400, 200), color=255)
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 36)
except Exception:
    font = ImageFont.load_default()

text = "1.5  0.0 -1.5\n2.0  0.0 -2.0\n1.5  0.0 -1.5"
d.text((20, 20), text, fill=0, font=font)
img.save('/app/kernel.png')
EOF
    python3 /tmp/make_image.py

    # Create the C library
    cat << 'EOF' > /tmp/filter.c
void apply_filter(double* input, int width, int height, double* kernel, double* output) {
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            double sum = 0.0;
            for (int ky = 0; ky < 3; ky++) {
                for (int kx = 0; kx < 3; kx++) {
                    int iy = y + ky - 1;
                    int ix = x + kx - 1;
                    if (iy >= 0 && iy < height && ix >= 0 && ix < width) {
                        sum += input[iy * width + ix] * kernel[ky * 3 + kx];
                    }
                }
            }
            output[y * width + x] = sum;
        }
    }
}
EOF
    gcc -shared -fPIC -O3 -o /home/user/libfilter.so /tmp/filter.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
