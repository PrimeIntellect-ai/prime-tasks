#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core tesseract-ocr
    pip3 install pytest pandas numpy pytesseract pillow flask fastapi uvicorn requests

    mkdir -p /app/logs

    # Generate the configuration screenshot
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -draw "text 10,30 'ETL CONFIGURATION DASHBOARD'" \
    -draw "text 10,60 'STATUS: OFFLINE'" \
    -draw "text 10,90 'TARGET_PORT: 8194'" \
    -draw "text 10,120 'RESAMPLE_INTERVAL: 10min'" \
    /app/config_screenshot.png

    # Generate the log data
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd

data = [
    ("2023-10-01 10:02:00", "A", 100.0),
    ("2023-10-01 10:05:00", "A", 120.0),
    ("2023-10-01 10:05:00", "A", 120.0), # duplicate
    ("2023-10-01 10:33:00", "A", 150.0), # gap from 10:10 to 10:30
    ("2023-10-01 10:04:00", "B", 200.0),
    ("2023-10-01 10:12:00", "B", 210.0),
    ("2023-10-01 10:12:00", "B", 210.0), # duplicate
]

df = pd.DataFrame(data, columns=["timestamp", "user_id", "latency"])
df.to_csv("/app/logs/etl_dump.csv", index=False)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
