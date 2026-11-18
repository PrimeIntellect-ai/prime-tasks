#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ make
pip3 install pytest Pillow

mkdir -p /app/configs

python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), '849302', fill=(0,0,0))
img.save('/app/auth_code.png')
"

cat << 'EOF' > /app/configs/server1.csv
ServerName,OS_VERSION,DB_PASSWORD,CACHE_SIZE
prod-srv-01,Ubuntu 22.04,super_secure_db_pass,1024
EOF

cat << 'EOF' > /tmp/server2.csv
ServerName,API_TOKEN,MAX_WORKERS,ADMIN_USER
win-srv-02,abc123xyz_token,64,sysadmin
EOF

iconv -f UTF-8 -t UTF-16LE /tmp/server2.csv > /app/configs/server2.csv
rm /tmp/server2.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
