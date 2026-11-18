#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc tar gzip zip
pip3 install pytest

mkdir -p /app
# Create blueprint image
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'PROTOTYPE BLUEPRINT' text 20,100 'SCALE: 1.75' text 20,150 'CONFIDENTIAL'" /app/blueprint.png

# Create data archive
mkdir -p /tmp/raw_data/subdir1 /tmp/raw_data/subdir2
cat << 'EOF' > /tmp/raw_data/file1.gcode
; TYPE: PART
G1 X10.0 Y20.0 Z5.0 E1.2
G1 X12.5 Y22.5 Z5.0 E1.5
EOF

cat << 'EOF' > /tmp/raw_data/subdir1/file2.gcode
; TYPE: PART
G1 X1.0 Y2.0 Z3.0
G0 X0 Y0 Z0
EOF

cat << 'EOF' > /tmp/raw_data/subdir2/invalid.gcode
; TYPE: SUPPORT
G1 X10.0 Y20.0 Z5.0
EOF

echo "Random text" > /tmp/raw_data/notes.txt

cd /tmp && tar -czf /app/data.tar.gz raw_data
rm -rf /tmp/raw_data

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
