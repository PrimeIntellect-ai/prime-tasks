#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-liberation
pip3 install pytest pillow

mkdir -p /app

cat << 'EOF' > /app/oracle.py
#!/usr/bin/env python3
import sys
import json

def process():
    line = sys.stdin.read().strip()
    if not line: return
    data = json.loads(line)

    name = data.get("name", "")
    strings = data.get("strings", {})

    total_keys = len(strings)
    null_keys = sum(1 for v in strings.values() if v is None)

    sys.stderr.write(f"[INFO] Processed user: {name}, nulls: {null_keys}\n")

    for k, v in strings.items():
        if v is None:
            if k == "greeting":
                strings[k] = f"Bonjour, {name}!"
            elif k == "error":
                strings[k] = f"Erreur de connexion pour {name}"
        else:
            # Encoding fixes
            v = v.replace("Ã©", "é").replace("Ã¨", "è").replace("Ã§", "ç")
            strings[k] = v

    data["stats"] = {
        "total_keys": total_keys,
        "null_keys": null_keys
    }

    print(json.dumps(data, separators=(',', ':')))

if __name__ == "__main__":
    process()
EOF

chmod +x /app/oracle.py

cat << 'EOF' > /tmp/make_video.py
from PIL import Image, ImageDraw, ImageFont
import subprocess

slides = [
    "ENCODING FIXES:\nÃ© -> é\nÃ¨ -> è\nÃ§ -> ç",
    "IMPUTATION RULES:\ngreeting -> Bonjour, {name}!\nerror -> Erreur de connexion pour {name}",
    "SUMMARY STATS REQUIRED:\ntotal_keys\nnull_keys"
]

font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 40)

for i, text in enumerate(slides):
    img = Image.new('RGB', (800, 600), color='white')
    d = ImageDraw.Draw(img)
    d.text((50,50), text, fill='black', font=font)
    img.save(f'/tmp/slide_{i}.png')

subprocess.run("ffmpeg -y -framerate 1/2 -i /tmp/slide_%d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/loc_rules.mp4", shell=True, check=True)
EOF

python3 /tmp/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
