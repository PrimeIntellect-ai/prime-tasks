#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core gcc libssl-dev
pip3 install pytest

mkdir -p /app/webroot/api

# Create baseline files
echo "<html><body>Welcome to the web server</body></html>" > /app/webroot/index.html
echo "body { background-color: #f0f0f0; }" > /app/webroot/style.css

# Generate users.json and golden_redacted_dump.txt
cat << 'EOF' > /app/generate_data.py
import json
import random
import re

def generate_cc():
    fmt = random.choice([0, 1, 2])
    digits = "".join([str(random.randint(0, 9)) for _ in range(16)])
    if fmt == 0:
        return digits
    elif fmt == 1:
        return f"{digits[:4]}-{digits[4:8]}-{digits[8:12]}-{digits[12:]}"
    else:
        return f"{digits[:4]} {digits[4:8]} {digits[8:12]} {digits[12:]}"

lines = []
for i in range(10000):
    obj = {
        "id": random.randint(100000, 999999),
        "name": f"User_{i}",
        "data": "benign data " + str(random.randint(100, 999))
    }
    if i < 500:
        obj["cc"] = generate_cc()
    lines.append(json.dumps(obj))

random.shuffle(lines)
text = "\n".join(lines)

with open("/app/webroot/api/users.json", "w") as f:
    f.write(text)

pattern = r'\b\d{16}\b|\b\d{4}-\d{4}-\d{4}-\d{4}\b|\b\d{4} \d{4} \d{4} \d{4}\b'
def replacer(m):
    return re.sub(r'\d', 'X', m.group(0))

redacted_text = re.sub(pattern, replacer, text)
with open("/app/golden_redacted_dump.txt", "w") as f:
    f.write(redacted_text)
EOF

python3 /app/generate_data.py

# Create manifest
cd /app/webroot
sha256sum index.html > /app/manifest.sha256
sha256sum style.css >> /app/manifest.sha256
# Add tampered hash for users.json (invalid hash)
echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  api/users.json" >> /app/manifest.sha256
cd /

# Generate breach console video
ffmpeg -f lavfi -i color=c=black:s=800x600:d=5 \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='[LOG] System startup complete':fontcolor=white:fontsize=18:x=10:y=10, \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='[LOG] Listening on port 443':fontcolor=white:fontsize=18:x=10:y=35, \
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='New connection established from 203.0.113.88 on port 443':fontcolor=green:fontsize=18:x=10:y=60:enable='between(t,2,5)'" \
    -c:v libx264 -y /app/breach_console.mp4

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
