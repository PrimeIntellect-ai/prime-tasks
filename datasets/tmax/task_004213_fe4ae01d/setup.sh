#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y ffmpeg tesseract-ocr imagemagick gawk fonts-dejavu-core tar coreutils

    mkdir -p /app/tmp
    cd /app/tmp

    # Create base.ini
    cat << 'EOF' > base.ini
[Core]
Version=1.0
[Modules]
Auth=true
EOF

    # Compress and encode
    tar -czf base.tar.gz base.ini
    base64 -w 0 base.tar.gz > base64.txt

    # Split into 5 chunks
    len=$(wc -c < base64.txt)
    part_len=$(( (len + 4) / 5 ))
    split -b $part_len -d base64.txt chunk_

    # Create images
    for i in 00 01 02 03 04; do
        text=$(cat chunk_$i)
        convert -size 800x600 xc:white -font DejaVu-Sans -pointsize 24 -fill black -gravity center -annotate +0+0 "$text" frame_${i}.png
    done

    # Create video
    ffmpeg -framerate 0.5 -i frame_%02d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/config_scroll.mp4

    cd /
    rm -rf /app/tmp

    # Create oracle script
    cat << 'EOF' > /app/oracle.py
import sys
from collections import defaultdict

config = defaultdict(dict)
current_section = None

try:
    with open('/home/user/base.ini', 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';') or line.startswith('#'): continue
            if line.startswith('[') and line.endswith(']'):
                current_section = line[1:-1]
            elif '=' in line and current_section:
                k, v = line.split('=', 1)
                config[current_section][k.strip()] = v.strip()
except FileNotFoundError:
    pass

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split(' ', 3)
    cmd = parts[0]
    if cmd == 'ADD' and len(parts) >= 4:
        sec, k, v = parts[1], parts[2], parts[3]
        config[sec][k] = v
    elif cmd == 'MOD' and len(parts) >= 4:
        sec, k, v = parts[1], parts[2], parts[3]
        if sec in config and k in config[sec]:
            config[sec][k] = v
    elif cmd == 'DEL' and len(parts) >= 3:
        sec, k = parts[1], parts[2]
        if sec in config and k in config[sec]:
            del config[sec][k]

for sec in sorted(config.keys()):
    print(f"[{sec}]")
    for k in sorted(config[sec].keys()):
        print(f"{k}={config[sec][k]}")
EOF

    cat << 'EOF' > /app/oracle_apply.sh
#!/bin/bash
python3 /app/oracle.py
EOF
    chmod +x /app/oracle_apply.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
