#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest pytesseract websockets Pillow

    mkdir -p /app
    mkdir -p /home/user/legacy_lib
    mkdir -p /home/user/tests

    # Generate the image with text X7B9K2M4P1Q8
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'X7B9K2M4P1Q8', fill=(0,0,0))
img.save('/app/project_auth.png')
"

    # Create the C file
    cat << 'EOF' > /home/user/legacy_lib/custom_hash.c
#include <string.h>

// Simple custom hash that sums ascii values and applies a modulo.
// Takes a string, returns an integer.
int compute_hash(const char* input) {
    int sum = 0;
    for(int i = 0; i < strlen(input); i++) {
        sum += (int)input[i];
    }
    return sum % 256;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
