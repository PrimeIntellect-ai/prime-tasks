#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc

    pip3 install pytest pytesseract Pillow lief

    mkdir -p /app/binaries

    # Generate the threat intel image
    # Note: ImageMagick default security policy might block some operations, but simple text drawing usually works.
    # To be safe, we can use a simpler approach or just modify policy if needed, but this should work.
    convert -size 600x300 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 10,30 'THREAT INTEL ADVISORY'" \
        -draw "text 10,60 'Watch out for the following malicious subnets:'" \
        -draw "text 10,90 '172.16.45.0/24'" \
        -draw "text 10,120 '10.99.0.0/16'" \
        -draw "text 10,150 '198.51.100.0/24'" \
        /app/threat_intel.png

    # Generate binaries and ground truth
    cat << 'EOF' > /tmp/generate.py
import os
import random
import json
import subprocess

malicious_subnets = ["172.16.45.", "10.99.", "198.51.100."]
malicious_files = []

for i in range(100):
    is_malicious = i < 30
    if is_malicious:
        subnet = random.choice(malicious_subnets)
        if subnet == "172.16.45.":
            ip = f"{subnet}{random.randint(1, 254)}"
        elif subnet == "10.99.":
            ip = f"{subnet}{random.randint(0, 255)}.{random.randint(1, 254)}"
        else:
            ip = f"{subnet}{random.randint(1, 254)}"
    else:
        if random.random() < 0.5:
            ip = f"8.8.8.{random.randint(1, 254)}"
        else:
            ip = "NO_IP"

    filename = f"bin_{i:03d}"
    filepath = f"/app/binaries/{filename}"

    c_code = f"""
    #include <stdio.h>
    int main() {{
        const char* my_str = "{ip}";
        return 0;
    }}
    """
    c_path = f"/tmp/{filename}.c"
    with open(c_path, "w") as f:
        f.write(c_code)

    subprocess.run(["gcc", c_path, "-o", filepath])

    if is_malicious:
        malicious_files.append(filename)

with open("/app/ground_truth.json", "w") as f:
    json.dump(malicious_files, f)
EOF

    python3 /tmp/generate.py
    rm -f /tmp/generate.py /tmp/*.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
