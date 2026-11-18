#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest Pillow

    mkdir -p /app /home/user

    # Create the raw logs
    cat << 'EOF' > /app/raw_logs.csv
timestamp,ip_address,response_time,cpu_load
0,192.168.1.1,100,45.0
1,10.0.0.1,150,
2,172.16.0.1,200,50.0
3,999.999.999.999,500,99.0
4,192.168.1.5,120,
5,10.0.0.2,130,48.0
6,invalid_ip,900,
7,172.16.0.2,180,
8,192.168.1.10,160,55.0
9,10.0.0.3,140,
EOF

    # Create the video frames and video
    python3 -c '
from PIL import Image
for i in range(10):
    color = "white" if i in [2, 7] else "black"
    img = Image.new("RGB", (100, 100), color)
    img.save(f"/tmp/frame_{i:03d}.png")
'

    ffmpeg -y -framerate 1 -i /tmp/frame_%03d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/server_dashboard.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
