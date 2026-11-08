#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest Pillow opencv-python-headless

mkdir -p /app
cat << 'EOF' > /app/setup.py
import os
import json
import subprocess
from PIL import Image

# 1. Generate Video
weights = [12, 45, 233, 110, 0, 55, 99, 128, 255, 64, 32, 16, 8, 4, 2, 100, 200, 150, 75, 37, 18, 9, 140, 210, 180, 90, 45, 22, 11, 250]
os.makedirs("/app/frames", exist_ok=True)
for i, w in enumerate(weights):
    img = Image.new('RGB', (64, 64), color=(w, 0, 0))
    # Avoid curly braces for f-string by using string concatenation
    img.save("/app/frames/frame_" + str(i).zfill(3) + ".png")

subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", "/app/frames/frame_%03d.png",
    "-c:v", "libx264", "-pix_fmt", "yuv444p", "-qp", "0", "/app/module_weights.mp4"
], check=True)

# 2. Create Oracle
oracle_code = "#!/usr/bin/env python3\n"
oracle_code += "import sys, json\n\n"
oracle_code += "def main():\n"
oracle_code += "    weights = " + str(weights) + "\n"
oracle_code += "    try:\n"
oracle_code += "        data = json.loads(sys.argv[1])\n"
oracle_code += "        cost = sum(m['size'] * weights[m['id']] for m in data['modules'])\n"
oracle_code += "        print(json.dumps({'schema_version': 2, 'build_cost': cost}))\n"
oracle_code += "    except Exception as e:\n"
oracle_code += "        sys.exit(1)\n\n"
oracle_code += "if __name__ == '__main__':\n"
oracle_code += "    main()\n"

with open("/app/oracle_estimate", "w") as f:
    f.write(oracle_code)
os.chmod("/app/oracle_estimate", 0o755)
EOF

python3 /app/setup.py
rm -rf /app/frames /app/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
