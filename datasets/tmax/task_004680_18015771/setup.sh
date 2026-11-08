#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ make
    pip3 install pytest Pillow pandas numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import struct
import os
from PIL import Image, ImageDraw

# 1. Create the Image
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "MACHINE CALIBRATION SPEC\nX_SCALE: 1.05\nY_SCALE: 0.95", fill=(0,0,0))
img.save('/app/calibration.png')

# 2. Create the GCode and Binary Archive
gcode_files = {
    "part_A.gcode": "G0 X10 Y10 Z0\nG1 X20 Y10 E1.5\nG1 X20 Y20 E3.0\nG1 X10 Y20 E4.5\nG1 X10 Y10 E6.0\nG0 Z5\n",
    "part_B.gcode": "G0 X0 Y0 Z0\nG1 X50 Y50 Z10 E15.5\n",
    "part_C.gcode": "G1 X-5 Y-5 Z0 E0.1\nG1 X5 Y5 Z2 E2.2\n"
}

with open('/app/artifacts.bin', 'wb') as f:
    f.write(b'ARTF')
    f.write(struct.pack('<I', len(gcode_files)))
    for name, content in gcode_files.items():
        name_bytes = name.encode('ascii')
        f.write(struct.pack('B', len(name_bytes)))
        f.write(name_bytes)
        content_bytes = content.encode('ascii')
        f.write(struct.pack('<I', len(content_bytes)))
        f.write(content_bytes)

# 3. Calculate Ground Truth
with open('/app/ground_truth.csv', 'w') as f:
    f.write("filename,volume,max_extrusion\n")
    f.write("part_A.gcode,498.7500,6.0000\n")
    f.write("part_B.gcode,24937.5000,15.5000\n")
    f.write("part_C.gcode,199.5000,2.2000\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
