#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest flask fastapi uvicorn requests pillow

    mkdir -p /app

    # Create encoder.c
    cat << 'EOF' > /app/encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* encode_payload(const char* payload, const char* platform, const char* seed) {
    // Basic concatenation to simulate encoding for the test
    char* result = malloc(1024);
    if (!result) return NULL;
    snprintf(result, 1024, "%s_%s_%s", platform, payload, seed);
    return result;
}
EOF

    # Create the image with the secret seed
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 50), color='white')
d = ImageDraw.Draw(img)
d.text((10, 20), 'CI_SECRET_SEED: X9F-44A-B21', fill='black')
# Resize to make it readable by tesseract
img = img.resize((800, 200), Image.Resampling.NEAREST)
img.save('/app/ci_architecture.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
