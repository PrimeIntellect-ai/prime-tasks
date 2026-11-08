#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr libgsl-dev fonts-dejavu-core gcc libc6-dev
pip3 install pytest flask

mkdir -p /app

# Generate config image
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'K_FOLDS=5'" -draw "text 10,100 'LAMBDA_VALS=0.1,0.5,1.0,5.0'" /app/config.png

# Generate CSV data
cat << 'EOF' > /app/data.csv
1.0,2.1,3.2,4.5
1.1,2.0,3.3,4.6
0.9,2.2,3.1,4.4
1.5,2.5,3.8,5.0
1.2,2.1,3.4,4.5
0.8,1.9,2.9,4.1
1.3,2.4,3.5,4.8
1.0,2.0,3.1,4.3
1.4,2.3,3.6,4.7
1.1,2.2,3.3,4.6
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
