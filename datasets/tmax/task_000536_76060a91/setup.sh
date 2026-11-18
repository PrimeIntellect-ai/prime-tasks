#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        tesseract-ocr-eng \
        netcat-openbsd \
        socat \
        gcc \
        fonts-dejavu-core

    pip3 install pytest Pillow

    mkdir -p /app

    # Generate ransom.png using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
try:
    fnt = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
except:
    fnt = ImageFont.load_default()
d.text((10,50), 'SYSTEM COMPROMISED. COMMUNICATE ON PORT 8443.', font=fnt, fill=(0,0,0))
img.save('/app/ransom.png')
"

    # Generate upload_handler.bin
    cat << 'EOF' > /tmp/upload_handler.c
#include <stdio.h>
int main() {
    char *dir = "/var/www/internal_uploads/";
    printf("Upload dir: %s\n", dir);
    return 0;
}
EOF
    gcc /tmp/upload_handler.c -o /app/upload_handler.bin
    rm /tmp/upload_handler.c

    # Generate compromised_logs.txt
    cat << 'EOF' > /app/compromised_logs.txt
GET /admin HTTP/1.1
Host: internal.corp
Cookie: session_token=aB9fK392jsL
User-Agent: Mozilla/5.0

GET /upload HTTP/1.1
Host: internal.corp
Cookie: session_token=99283hHJs12
User-Agent: curl/7.68.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
