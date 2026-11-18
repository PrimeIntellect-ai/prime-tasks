#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr build-essential libomp-dev
pip3 install pytest pillow

mkdir -p /app
mkdir -p /home/user

# Generate the RNA dataset
python3 -c '
import random
random.seed(42)
with open("/home/user/rna_data.csv", "w") as f:
    f.write("Sequence\n")
    for _ in range(5000):
        length = random.randint(50, 150)
        seq = "".join(random.choices(["A", "U", "G", "C"], k=length))
        f.write(f"{seq}\n")
'

# Generate the kinetics image
python3 -c '
from PIL import Image, ImageDraw
img = Image.new("RGB", (200, 150), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Kinetic Parameters:\nk_base: 0.010\nk_A: 0.025\nk_U: 0.015\nk_G: 0.030\nk_C: 0.040"
d.text((10,10), text, fill=(0,0,0))
# Resize to make the text larger and easier for tesseract to read
img = img.resize((600, 450), Image.NEAREST)
img.save("/app/kinetics.png")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
