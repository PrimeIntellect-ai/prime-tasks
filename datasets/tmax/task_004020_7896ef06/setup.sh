#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest pytz pillow

mkdir -p /app
cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "SYSTEM ALERT CONFIGURATION V3\nRegion: Asia/Tokyo\nMax Load: 82.5\nProcess: worker_daemon"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/alert_config.png')
EOF
python3 /tmp/gen_image.py

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/init_env.sh
#!/bin/bash
echo "INITIALIZED=1" > /tmp/.env_ready
exit 0
EOF

cat << 'EOF' > /home/user/generate_logs.py
#!/usr/bin/env python3
import sys, os, time, random
from datetime import datetime, timedelta

if not os.path.exists('/tmp/.env_ready'):
    sys.stderr.write("Fatal: Environment not initialized.\n")
    sys.exit(1)

# Deterministic seed for verification
random.seed(42)
start_time = datetime(2023, 10, 1, 0, 0, 0)

processes = ['worker_daemon', 'web_server', 'db_writer']

for i in range(5000):
    current_time = start_time + timedelta(minutes=i)
    proc = random.choice(processes)
    load = round(random.uniform(10.0, 99.9), 1)

    # Simulate a crash midway to test restart policy
    if i == 2500 and not os.path.exists('/tmp/.crashed_once'):
        with open('/tmp/.crashed_once', 'w') as f:
            f.write('1')
        sys.exit(2)

    print(f"{current_time.strftime('%Y-%m-%d %H:%M:%S')}|{proc}|{load}")

sys.exit(0)
EOF

chmod +x /home/user/init_env.sh
chmod +x /home/user/generate_logs.py
chmod -R 777 /home/user
