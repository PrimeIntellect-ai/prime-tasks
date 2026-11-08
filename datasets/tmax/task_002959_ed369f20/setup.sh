#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/incoming
    mkdir -p /app/artifact_repo/safe_zone

    touch -d "2 days ago" /app/incoming/data1.dat
    touch -d "1 day ago" /app/incoming/data2.dat
    touch -d "10 days ago" /app/incoming/old.dat

    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'Base Directory: /app/artifact_repo/safe_zone'" /app/policy.png

    cat << 'EOF' > /app/oracle_parser.py
import sys
import json
import os

BASE_DIR = os.path.abspath("/app/artifact_repo/safe_zone")

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    for item in data:
        if not isinstance(item, dict) or "path" not in item:
            continue
        original_path = item["path"]
        resolved_path = os.path.abspath(os.path.join(BASE_DIR, original_path))
        try:
            common = os.path.commonpath([BASE_DIR, resolved_path])
        except ValueError:
            common = ""
        if common == BASE_DIR and resolved_path != BASE_DIR:
            print(resolved_path)
        else:
            print(f"REJECTED: {original_path}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
