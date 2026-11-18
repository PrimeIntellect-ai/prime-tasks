#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr build-essential cmake
    pip3 install pytest Pillow pyinstaller

    mkdir -p /app

    # Generate the legacy_rules.png image using Python and Pillow to avoid ImageMagick policy issues
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color='white')
d = ImageDraw.Draw(img)
d.text((20,50), "Proprietary Pre-release weights:", fill="black")
d.text((20,80), "'dev' = 1, 'alpha' = 2, 'beta' = 3, 'rc' = 4, 'final' = 5.", fill="black")
d.text((20,110), "Any missing pre-release tag defaults to 'final' (5).", fill="black")
d.text((20,140), "Format is MAJOR.MINOR.PATCH-PRERELEASE.", fill="black")
img.save('/app/legacy_rules.png')
EOF
    python3 /tmp/gen_image.py

    # Create the oracle script
    cat << 'EOF' > /tmp/oracle.py
import sys
import re

def get_weight(tag):
    mapping = {'dev': 1, 'alpha': 2, 'beta': 3, 'rc': 4, 'final': 5}
    return mapping.get(tag, 5)

def parse_version(v):
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z]+))?$', v)
    if not m: return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), get_weight(m.group(4)), v)

for line in sys.stdin:
    versions = line.strip().split()
    parsed = []
    for v in versions:
        p = parse_version(v)
        if p:
            parsed.append(p)
    # Sort descending
    parsed.sort(key=lambda x: (x[0], x[1], x[2], x[3]), reverse=True)

    sorted_strs = [p[4] for p in parsed]
    print(" ".join(sorted_strs))

    diffs = []
    for i in range(len(parsed)-1):
        v1 = parsed[i]
        v2 = parsed[i+1]
        diffs.append(f"{v1[4]} -> {v2[4]} (diff {v1[0]-v2[0]}, diff {v1[1]-v2[1]}, diff {v1[2]-v2[2]})")
    if diffs:
        print(" ".join(diffs))
    else:
        print("")
EOF

    # Compile the oracle script
    pyinstaller --onefile /tmp/oracle.py --distpath /app --name semver_oracle
    chmod +x /app/semver_oracle

    # Clean up
    rm -rf /tmp/oracle.py /tmp/gen_image.py /build /oracle.spec

    # Setup user and permissions
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/vparser_cpp
    chmod -R 777 /home/user
