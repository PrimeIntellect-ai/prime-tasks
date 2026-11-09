#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl imagemagick ffmpeg fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /app/trusted_roots.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Corp/CN=telemetry.internal.corp"

    # Generate the video fixture showing the iptables command
    convert -size 800x600 xc:black -font DejaVu-Sans-Mono -pointsize 24 -fill white -draw "text 50,50 'root@host:~# iptables -A OUTPUT -p tcp --dport 8443 -j DROP'" /tmp/frame.png
    ffmpeg -loop 1 -i /tmp/frame.png -c:v libx264 -t 5 -pix_fmt yuv420p /app/attack_recording.mp4

    # Create the oracle script for fuzz_equivalence
    cat << 'EOF' > /app/oracle.py
import sys
import re

def process():
    for line in sys.stdin:
        if '8443' in line:
            continue

        line = re.sub(r'--password \S+', '--password REDACTED', line)
        line = re.sub(r'Cookie: \S+', 'Cookie: REDACTED', line)
        line = re.sub(r'Authorization: Bearer \S+', 'Authorization: Bearer REDACTED', line)

        if 'telemetry.internal.corp' in line:
            line = line.rstrip('\n') + ' [TRUSTED]\n'

        sys.stdout.write(line)

if __name__ == '__main__':
    process()
EOF
    chmod +x /app/oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
