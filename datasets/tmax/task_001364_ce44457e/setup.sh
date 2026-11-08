#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Fix ImageMagick policy to allow writing to PDF/PNG if needed, though usually default allows PNG
    sed -i 's/<policy domain="coder" rights="none" pattern="PDF" \/>/<!-- <policy domain="coder" rights="none" pattern="PDF" \/> -->/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 20,50 'API_BASE: \"https://secure.backend.local\"'" -draw "text 20,100 'MIN_VERSION: \"2.1.0\"'" /app/schema.png

    cat << 'EOF' > /home/user/reference.py
import sys

# Replace these with the actual values from /app/schema.png
API_BASE = "PLACEHOLDER_URL" 
MIN_VERSION = "0.0.0"

def compare_versions(v1, v2):
    parts1 = [int(x) for x in v1.split('.')]
    parts2 = [int(x) for x in v2.split('.')]
    return parts1 >= parts2

def process(path, version):
    if not compare_versions(version, MIN_VERSION):
        return "ERROR: Version too old"

    if "?" in path:
        base_path, query = path.split("?", 1)
        params = query.split("&")
        param_str = ", ".join(params)
    else:
        base_path = path
        param_str = "none"

    return f"ROUTED: {API_BASE}{base_path} PARAMS: {param_str}"

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    print(process(sys.argv[1], sys.argv[2]))
EOF

    cat << 'EOF' > /app/oracle_router
#!/usr/bin/env python3
import sys
API_BASE = "https://secure.backend.local"
MIN_VERSION = "2.1.0"
def compare_versions(v1, v2):
    parts1 = [int(x) for x in v1.split('.')]
    parts2 = [int(x) for x in v2.split('.')]
    return parts1 >= parts2
def process(path, version):
    if not compare_versions(version, MIN_VERSION):
        return "ERROR: Version too old"
    if "?" in path:
        base_path, query = path.split("?", 1)
        params = query.split("&")
        param_str = ", ".join(params)
    else:
        base_path = path
        param_str = "none"
    return f"ROUTED: {API_BASE}{base_path} PARAMS: {param_str}"
if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(1)
    print(process(sys.argv[1], sys.argv[2]))
EOF

    chmod +x /app/oracle_router

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
