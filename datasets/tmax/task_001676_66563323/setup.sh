#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc imagemagick fonts-dejavu-core
    pip3 install pytest matplotlib

    mkdir -p /app
    cat << 'EOF' > /app/reference.csv
node,expected_time
0,5.0000
1,3.3333
2,5.0000
3,5.0000
4,10.0000
EOF

    # Create the image with imagemagick
    # Fix ImageMagick policy if needed
    sed -i 's/rights="none" pattern=".*"/rights="read|write" pattern="*"/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 200x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,30 '0 1\n1 2\n2 3\n3 0\n1 4'" /app/molecule_data.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
