#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc build-essential
pip3 install pytest pillow

mkdir -p /app
mkdir -p /tmp/frames

# Generate video frames using Python to avoid ImageMagick policy issues
python3 -c "
from PIL import Image
for i in range(32):
    color = 'white' if i in [26, 28, 30] else 'black'
    img = Image.new('RGB', (100, 100), color)
    img.save(f'/tmp/frames/frame_{i:02d}.png')
"

# Create the video
ffmpeg -framerate 1 -i /tmp/frames/frame_%02d.png -c:v libx264 -pix_fmt yuv420p /app/config_signal.mp4
rm -rf /tmp/frames

# Generate GCode file
python3 -c "
import random
random.seed(42)
with open('/app/base_toolpath.gcode', 'w') as f:
    f.write('; START GCODE\n')
    for _ in range(1000):
        x = round(random.uniform(-100, 100), 3)
        y = round(random.uniform(-100, 100), 3)
        f.write(f'G1 X{x} Y{y}\n')
    f.write('; END GCODE\n')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
