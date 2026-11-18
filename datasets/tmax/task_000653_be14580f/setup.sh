#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make
    pip3 install pytest Pillow

    mkdir -p /home/user/dataset /home/user/web /home/user/extracted /app /tmp/frames

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
from PIL import Image

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(1, 101):
    color = 'white' if i in [20, 40, 60] else 'black'
    img = Image.new('RGB', (64, 64), color)
    img.save(f'/tmp/frames/frame_{i:03d}.png')

with open('/tmp/print.gcode', 'w') as f:
    f.write("G1 X10 Y10 E1.5\nG1 X20 Y20 E2.0\nG1 X30 Y30 E0.5\n")

with open('/tmp/machine.log', 'w') as f:
    f.write("[2023-10-01 10:00:00]\nStatus:\nPrinting\n[2023-10-01 11:00:00]\nStatus:\nFinished\n")

with open('/tmp/malicious_file.txt', 'w') as f:
    f.write("bad")

with tarfile.open('/home/user/dataset/job.tar', 'w') as tar:
    tar.add('/tmp/print.gcode', arcname='print.gcode')
    tar.add('/tmp/machine.log', arcname='machine.log')
    tar.add('/tmp/malicious_file.txt', arcname='../malicious_file.txt')
EOF

    python3 /tmp/setup.py
    ffmpeg -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/print_video.mp4

    rm -rf /tmp/frames /tmp/setup.py /tmp/print.gcode /tmp/machine.log /tmp/malicious_file.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
