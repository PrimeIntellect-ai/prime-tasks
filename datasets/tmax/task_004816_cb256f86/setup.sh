#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,value
2023-10-01 10:00:00,S1,10.0
2023-10-01 10:00:00,S1,10.0
2023-10-01 10:05:00,S1,
2023-10-01 10:07:00,S2,5.0
2023-10-01 10:10:00,S1,20.0
2023-10-01 10:12:00,S1,22.0
2023-10-01 10:20:00,S1,30.0
EOF

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'SYSTEM CONFIGURATION DASHBOARD\nAGGREGATION INTERVAL: 15min\nAPI TOKEN: secr3t_T0k3n_99'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/config.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
