#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr gcc make
pip3 install pytest

mkdir -p /app
convert -size 200x100 xc:white -fill black -pointsize 24 -draw "text 10,30 'WINDOW=3' text 10,60 'IGNORE=DROP'" /app/config.png

mkdir -p /home/user
cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/dataset.csv
100,café,10.0
101,apple,5.0
102,café,15.0
103,DROP,100.0
104,café,12.5
105,apple,5.0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
