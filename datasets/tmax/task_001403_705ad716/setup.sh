#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow pytesseract

    mkdir -p /app/data/clean /app/data/evil /app/eval/clean /app/eval/evil

    cat << 'EOF' > /tmp/setup_env.py
import os
import zipfile
import hashlib
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "Project Salt: KAPPA_99_OMEGA", fill=(0, 0, 0))
img.save('/app/lab_notes.png')

salt = b"KAPPA_99_OMEGA"

def make_zip(path, files, manifest_content=None, signature_content=None, corrupt=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)

    if manifest_content is None:
        manifest_lines = []
        for fname, fcontent in files.items():
            if fname not in ['manifest.txt', 'signature.txt']:
                sha256 = hashlib.sha256(fcontent).hexdigest()
                manifest_lines.append(f"{fname} {sha256}")
        manifest_content = "\n".join(manifest_lines).encode()

    if signature_content is None:
        signature_content = hashlib.sha256(manifest_content + salt).hexdigest().encode()

    files['manifest.txt'] = manifest_content
    files['signature.txt'] = signature_content

    with zipfile.ZipFile(path, 'w') as zf:
        for fname, fcontent in files.items():
            zf.writestr(fname, fcontent)

    if corrupt:
        with open(path, 'r+b') as f:
            f.seek(10)
            f.write(b'\x00\x00\x00\x00')

# Clean data
for i in range(5):
    make_zip(f'/app/data/clean/clean_{i}.zip', {f'file_{i}.dat': b'data'*i})
for i in range(5):
    make_zip(f'/app/eval/clean/eval_clean_{i}.zip', {f'file_{i}.dat': b'eval_data'*i})

# Evil data
make_zip('/app/data/evil/evil_0.zip', {'f.dat': b'1'}, corrupt=True)
make_zip('/app/data/evil/evil_1.zip', {'f.dat': b'1'}, manifest_content=b"f.dat " + hashlib.sha256(b'1').hexdigest().encode() + b"\nmissing.dat 5678")
make_zip('/app/data/evil/evil_2.zip', {'f.dat': b'1'}, manifest_content=b"f.dat 0000000000000000000000000000000000000000000000000000000000000000")
make_zip('/app/data/evil/evil_3.zip', {'f.dat': b'1', 'extra.dat': b'2'}, manifest_content=b"f.dat " + hashlib.sha256(b'1').hexdigest().encode())
make_zip('/app/data/evil/evil_4.zip', {'f.dat': b'1'}, signature_content=b"bad_sig")

# Eval evil
make_zip('/app/eval/evil/eval_evil_0.zip', {'f.dat': b'1'}, corrupt=True)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
