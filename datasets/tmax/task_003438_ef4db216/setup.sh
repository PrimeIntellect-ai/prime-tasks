#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil
    pip3 install pytest

    # Create the image fixture
    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'MAGIC: LOG_V1.0', fill=(0, 0, 0))
img.save('/app/spec.png')
"

    # Create required directories
    mkdir -p /home/user/active_logs /home/user/archive /home/user/.hidden

    # Create the background writer script
    cat << 'EOF' > /home/user/.hidden/writer.py
import time
import random
import sys
import fcntl

log_file = "/home/user/active_logs/app.log"
total_records = 1000

with open("/home/user/.hidden/truth_count.txt", "w") as f:
    f.write(str(total_records))

for i in range(total_records):
    lines = [f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] INFO Record {i}\n"]
    if random.random() < 0.3:
        lines.append("    at com.example.App.main(App.java:42)\n")
        lines.append("    at java.base/java.lang.Thread.run(Thread.java:833)\n")

    with open(log_file, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        for line in lines:
            f.write(line)
        f.flush()
        fcntl.flock(f, fcntl.LOCK_UN)
    time.sleep(0.01)
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
