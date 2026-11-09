#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server
pip3 install pytest flask redis requests

mkdir -p /home/user
useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import random
import hashlib

# Create directories
os.makedirs("/home/user/project_dump/assets", exist_ok=True)
os.makedirs("/app/services", exist_ok=True)

# Generate Mock Flask API
with open("/app/services/metadata_api.py", "w") as f:
    f.write("""
from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route('/get_name')
def get_name():
    h = request.args.get('hash', '')
    ext = request.args.get('ext', '')
    return jsonify({"filename": f"asset_{h[:8]}.{ext}"})
if __name__ == '__main__':
    app.run(port=5000)
""")

# Generate mock data
valid_signatures = {
    "png": b"\x89PNG\x0d\x0a\x1a\x0a",
    "jpg": b"\xff\xd8\xff\xe0",
    "pdf": b"%PDF-1.4"
}
manifest_lines = []

for i in range(500): # 500 files
    ext = random.choice(["png", "jpg", "pdf", "txt", "bin"])
    is_duplicate = random.random() < 0.3

    if not is_duplicate:
        content_tail = os.urandom(64)

    if ext in valid_signatures:
        content = valid_signatures[ext] + content_tail
    else:
        content = os.urandom(70)

    sub_dir = f"dir_{random.randint(1, 10)}"
    os.makedirs(f"/home/user/project_dump/assets/{sub_dir}", exist_ok=True)

    fake_ext = random.choice(["png", "jpg", "pdf", "txt", "mp3"]) # intentional mismatch
    filename = f"file_{i}.{fake_ext}"
    filepath = f"/home/user/project_dump/assets/{sub_dir}/{filename}"

    with open(filepath, "wb") as f:
        f.write(content)

    manifest_lines.append(f"Asset: assets/{sub_dir}/{filename}\n")

with open("/home/user/project_dump/manifest.txt", "w") as f:
    f.writelines(manifest_lines)

# Generate verifier
with open("/app/verify.py", "w") as f:
    f.write("""
import os
import re

total_valid = 0
correct_mapped = 0

with open('/home/user/project_dump/manifest.txt') as orig:
    orig_lines = orig.readlines()

try:
    with open('/home/user/manifest_updated.txt') as new_m:
        new_lines = new_m.readlines()
except FileNotFoundError:
    print("Score: 0.0")
    exit(1)

for orig_l, new_l in zip(orig_lines, new_lines):
    orig_path = orig_l.split('Asset: ')[1].strip()
    full_orig = os.path.join('/home/user/project_dump', orig_path)

    with open(full_orig, 'rb') as f:
        header = f.read(8)

    is_valid = False
    true_ext = ''
    if header.startswith(b'\\x89PNG\\x0d\\x0a\\x1a\\x0a'):
        is_valid = True
        true_ext = 'png'
    elif header.startswith(b'\\xff\\xd8\\xff'):
        is_valid = True
        true_ext = 'jpg'
    elif header.startswith(b'%PDF-'):
        is_valid = True
        true_ext = 'pdf'

    if is_valid:
        total_valid += 1
        new_path = new_l.split('Asset: ')[1].strip()
        if os.path.exists(new_path) and f"/organized/{true_ext}/" in new_path:
            correct_mapped += 1

score = correct_mapped / total_valid if total_valid > 0 else 0
print(f"Score: {score:.3f}")
""")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /app
chmod -R 777 /home/user
