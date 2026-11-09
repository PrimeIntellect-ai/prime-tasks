#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gdb strace ltrace binutils tesseract-ocr tesseract-ocr-eng
pip3 install pytest Pillow

mkdir -p /app

cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

float calculate_sqrt(float n) {
    float x = n;
    float y = 1.0f;
    // Convergence stops when difference is <= 0.001
    while (x - y > 0.001f) {
        x = (x + y) / 2;
        y = n / x;
    }
    return x;
}

int main() {
    uint32_t header = 0xCAFEBABE;
    fwrite(&header, sizeof(uint32_t), 1, stdout);

    int val;
    while (scanf("%d", &val) == 1) {
        float res = calculate_sqrt((float)val);
        fwrite(&res, sizeof(float), 1, stdout);
    }
    return 0;
}
EOF

gcc -O0 -o /app/telemetry_oracle /app/oracle.c -lm
strip /app/telemetry_oracle
rm /app/oracle.c

python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 50), 'MAGIC HEADER: 0xCAFEBABE', fill='black')
img.save('/app/format_spec.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
