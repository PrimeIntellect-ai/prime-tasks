#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (0, 0, 0))
d = ImageDraw.Draw(img)
text = "SRE CI/CD Alert: Uptime policy enforcement.\nAll ext4 mounts must include 'errors=remount-ro'\nin their mount options to prevent VM corruption.\nIf missing, append it as the last option."
d.text((10,10), text, fill=(255,255,255))
img.save('/app/vnc_screenshot.png')
EOF
    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    mkdir -p /opt/verifier
    cat << 'EOF' > /opt/verifier/oracle.py
import sys

def process_fstab_line(line):
    line = line.strip()
    if not line or line.startswith('#'):
        return line

    parts = line.split()
    if len(parts) >= 4:
        fstype = parts[2]
        options = parts[3]
        if fstype == 'ext4':
            opts_list = options.split(',')
            if 'errors=remount-ro' not in opts_list:
                parts[3] = options + ',errors=remount-ro' if options else 'errors=remount-ro'

    return ' '.join(parts)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(process_fstab_line(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
