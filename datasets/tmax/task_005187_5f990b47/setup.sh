#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core libgsl-dev gcc make
    pip3 install pytest

    mkdir -p /app /home/user

    # Create the image with the calibration multiplier
    convert -size 400x100 xc:white -font DejaVu-Sans-Bold -pointsize 24 -fill black -draw "text 10,50 'CALIBRATION_MULTIPLIER=1.45'" /app/calibration.png

    # Generate the mock sensor data (1000 rows)
    python3 -c "
import random
random.seed(42)
with open('/home/user/sensor_data.csv', 'w') as f:
    for _ in range(1000):
        f.write(f'{random.gauss(10.0, 2.0)}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
