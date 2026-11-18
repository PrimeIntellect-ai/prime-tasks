#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu
    pip3 install pytest

    mkdir -p /app

    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,30 'CURATION POLICY' text 10,60 'ACTIVE REPO ID: SECURE-BIN-84' text 10,90 'DENY OVERWRITES'" /app/policy.png

    cat << 'EOF' > /app/oracle_sanitize.py
import sys
import os

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    target_dir = os.path.abspath(sys.argv[1])
    manifest = sys.argv[2]

    repo_id = "SECURE-BIN-84"

    with open(manifest, 'r') as f:
        for line in f:
            p = line.strip()
            if not p:
                continue

            # Simulated zip extraction logic: join target and relative path
            # To handle absolute paths in zip safely (treating as relative or dangerous)
            # Python's os.path.join drops the first part if the second is absolute.
            # So we manually strip leading slashes for the join.
            clean_p = p.lstrip('/')

            resolved = os.path.abspath(os.path.join(target_dir, clean_p))

            # Check if it's strictly inside the target_dir
            if resolved.startswith(target_dir + os.sep) and len(resolved) > len(target_dir + os.sep):
                print(f"[{repo_id}] {resolved}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_sanitize.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
