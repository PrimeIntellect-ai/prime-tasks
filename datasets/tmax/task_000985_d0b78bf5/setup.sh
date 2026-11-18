#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y tesseract-ocr imagemagick fonts-dejavu-core iproute2 cargo rustc sudo

    # Create /app directory
    mkdir -p /app

    # Generate VNC crash image
    convert -size 800x600 xc:black -font DejaVu-Sans-Mono -pointsize 24 -fill white -draw "text 50,50 'Kernel panic - not syncing: Fatal exception'" -draw "text 50,100 'PANIC: 0xDEADBEEF'" /app/vnc_crash.png

    # Generate metrics log
    python3 -c "
import random
random.seed(42)
with open('/app/metrics.log', 'w') as f:
    for i in range(10000):
        ts = 1600000000000 + i * 100
        status = 200 if random.random() < 0.8 else 500
        latency = random.uniform(10.0, 500.0) if status == 200 else random.uniform(500.0, 1000.0)
        f.write(f'{ts} {latency:.2f} {status}\n')
"

    # Create user
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Set permissions
    chmod -R 777 /home/user
    chmod 777 /app/vnc_crash.png /app/metrics.log
