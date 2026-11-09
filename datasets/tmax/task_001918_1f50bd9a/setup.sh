#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /app/raw_data.csv
id,category,raw_text,value
1,A,café,10.0
2,B,tést,15.0
3,A,fußball,20.0
4,B,æther,25.0
5,A,naïve,30.0
6,B,résumé,35.0
EOF

convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,100 'CONFIG: STRATA_SIZE=2, WINDOW=3, CRON=0 2 * * *'" /app/pipeline_config.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
