#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install --default-timeout=100 pytest Pillow

mkdir -p /app
mkdir -p /home/user/project

cat << 'EOF' > /home/user/project/legacy_parser.js
function evaluate(expr, R, G, B) {
    // simplified mock parser logic to be translated
    let replaced = expr.replace(/R/g, R).replace(/G/g, G).replace(/B/g, B);
    // In actual task, we expect them to build a safe evaluator, but the JS uses Function for simplicity of definition.
    return new Function('return ' + replaced)();
}
EOF

cat << 'EOF' > /tmp/gen_frames.py
from PIL import Image
import os
os.makedirs('/tmp/frames', exist_ok=True)
for i in range(100):
    r = (i * 5) % 256
    g = (i * 10) % 256
    b = (i * 15) % 256
    img = Image.new('RGB', (100, 100), color=(r, g, b))
    img.save(f'/tmp/frames/frame_{i:03d}.png')
EOF
python3 /tmp/gen_frames.py

ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/color_math.mp4
rm -rf /tmp/frames /tmp/gen_frames.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
