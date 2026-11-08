#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/oracle_log_parser.py
import sys
import re
import json

def parse_log(log_str):
    ip_pattern = r'(?:Connection closed by |Disconnecting from )(\d{1,3}(?:\.\d{1,3}){3})'
    ips = re.findall(ip_pattern, log_str)

    # Filter valid IPs mathematically
    valid_ips = []
    for ip in ips:
        parts = ip.split('.')
        if all(0 <= int(p) <= 255 for p in parts):
            valid_ips.append(ip)

    unique_ips = sorted(list(set(valid_ips)))
    key_failures = log_str.count('publickey')

    print(json.dumps({"failed_ips": unique_ips, "key_failures": key_failures}))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        parse_log(sys.argv[1])
    else:
        print(json.dumps({"failed_ips": [], "key_failures": 0}))
EOF

    # Generate the video
    ffmpeg -f lavfi -i color=c=black:s=640x480:r=30:d=60 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Node-3 KEY_REJECTED':fontcolor=red:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(n\,450\,452)+between(n\,900\,902)'" \
        -c:v libx264 -preset ultrafast -y /app/deployment_monitor.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
