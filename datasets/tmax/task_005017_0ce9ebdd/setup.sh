#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest Pillow pytesseract

mkdir -p /app/bin
cat << 'EOF' > /app/bin/oracle_optimizer
#!/usr/bin/env python3
import sys
def get_min_cost(gb, req):
    standard = gb * 0.0210
    infrequent = (gb * 0.0115) + (req * 0.0025)
    archive = (gb * 0.0035) + (req * 0.0250)
    return min(standard, infrequent, archive)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    gb, req = map(int, line.split())
    print(f"{get_min_cost(gb, req):.4f}")
EOF
chmod +x /app/bin/oracle_optimizer

# Adjust ImageMagick policy to ensure we can create images
sed -i 's/rights="none" pattern="LABEL"/rights="read|write" pattern="LABEL"/' /etc/ImageMagick-6/policy.xml || true
sed -i 's/rights="none" pattern="TEXT"/rights="read|write" pattern="TEXT"/' /etc/ImageMagick-6/policy.xml || true

convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +50+50 "Enterprise Storage Rates:\nStandard Tier: \$0.0210 per GB, \$0.0000 per request\nInfrequent Tier: \$0.0115 per GB, \$0.0025 per request\nArchive Tier: \$0.0035 per GB, \$0.0250 per request" /app/storage_rates.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
