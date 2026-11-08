#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-pandas \
        python3-numpy \
        r-base-core \
        imagemagick \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    # Generate CSV
    cat << 'EOF' > /tmp/gen_csv.py
import pandas as pd
import numpy as np
np.random.seed(42)
df = pd.DataFrame({
    'Temp': np.random.normal(50, 5, 100),
    'Pressure': np.random.normal(100, 10, 100),
    'Vibration': np.random.normal(5, 1, 100)
})
df['Pressure'] += df['Temp'] * 1.5 # introduce correlation
df.to_csv('/app/sensor_data.csv', index=False)
EOF
    python3 /tmp/gen_csv.py

    # Generate Image
    # Fix Imagemagick policy for PDF/fonts if needed, but xc:white should work
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,50 'API TOKEN: ZETA_99_OMEGA'" \
        -draw "text 20,100 'ALPHA: 0.02'" \
        -blur 0x1 /app/config_scan.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
