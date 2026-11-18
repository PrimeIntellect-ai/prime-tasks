#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr gcc
pip3 install pytest Pillow pytesseract

mkdir -p /app/uploads /app/safe /app/quarantine
cd /app

cat << 'EOF' > slow_organizer.py
import os
import shutil
import time
import json

def scan_content(content):
    if b"<script>" in content or b"DROP TABLE" in content:
        return False
    return True

def run():
    safe_count = 0
    quarantine_count = 0
    for filename in os.listdir("uploads"):
        filepath = os.path.join("uploads", filename)
        with open(filepath, "rb") as f:
            content = f.read()

        # Simulate some extra overhead present in the legacy version
        for _ in range(100):
            content.find(b"dummy_search_pattern")

        if scan_content(content):
            safe_count += 1
            # Not moving in slow to avoid ruining it for fast, just counting
        else:
            quarantine_count += 1

    with open("slow_results.json", "w") as f:
        json.dump({"safe_count": safe_count, "quarantine_count": quarantine_count}, f)

if __name__ == "__main__":
    run()
EOF

python3 -c '
import random
import os
random.seed(42)
for i in range(20000):
    is_malicious = random.random() < 0.05
    content = b"Regular file content with some padding " * 20
    if is_malicious:
        content += random.choice([b"<script>alert(1)</script>", b"SELECT * FROM users; DROP TABLE users;"])
    with open(f"uploads/file_{i}.txt", "wb") as f:
        f.write(content)
'

convert -background white -fill black -font Courier -pointsize 24 label:"struct ScanResult {\n    int is_safe;\n    double threat_score;\n    char file_hash[32];\n};" /app/spec.png

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
