#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
pip3 install pytest

mkdir -p /app
# Generate the video fixture
ffmpeg -f lavfi -i color=c=black:s=640x480:d=3 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='REVOKED ARTIFACTS\n\nREVOKED-1144\nREVOKED-3392\nREVOKED-8841':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -y /app/revocation_list.mp4

# Create the reference oracle
cat << 'EOF' > /app/oracle_filter.py
#!/usr/bin/env python3
import sys
import json
import os

REVOKED_IDS = {"REVOKED-1144", "REVOKED-3392", "REVOKED-8841"}

def is_safe(path):
    if path.startswith('/'): return False
    if '\0' in path: return False
    norm = os.path.normpath(path)
    if norm == '..' or norm.startswith('../'):
        return False
    return True

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        with open(sys.argv[1], 'r') as f:
            manifest = json.load(f)
    except Exception:
        sys.exit(1)

    artifact_id = manifest.get("artifact_id", "")
    if artifact_id in REVOKED_IDS:
        print("STATUS: REVOKED")
        return

    print("STATUS: APPROVED")

    for f in manifest.get("files", []):
        filename = f.get("filename", "")
        sha256 = f.get("sha256", "")
        if is_safe(filename):
            print(f"SAFE: {filename} - {sha256}")

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_filter.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
