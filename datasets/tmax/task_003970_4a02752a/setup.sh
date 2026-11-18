#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick fonts-liberation
pip3 install pytest

mkdir -p /app/frames
convert -size 800x600 xc:black -fill white -pointsize 40 -gravity center -annotate +0+0 "Max Validation Retries: 3" /app/frames/001.png
convert -size 800x600 xc:black -fill white -pointsize 40 -gravity center -annotate +0+0 "Sequence: INIT -> BUILD -> LINK -> TEST -> DEPLOYED" /app/frames/002.png
ffmpeg -framerate 1 -i /app/frames/%03d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/release_demo.mp4
rm -rf /app/frames

cat << 'EOF' > /opt/oracle.py
#!/usr/bin/env python3
import sys

def main():
    max_retries = 3
    retries = 0
    expected_sequence = ["INIT", "BUILD", "LINK", "TEST", "DEPLOYED"]
    current_index = 0

    for line in sys.stdin:
        line = line.strip()
        if line == "VALIDATION_FAILED":
            retries += 1
            if retries > max_retries:
                print("RATE_LIMIT_EXCEEDED")
                sys.exit(1)
        elif line.startswith("STATE: "):
            state = line.split("STATE: ")[1].strip()
            if current_index < len(expected_sequence) and state == expected_sequence[current_index]:
                current_index += 1
                if current_index == len(expected_sequence):
                    print("SUCCESS")
                    sys.exit(0)
            else:
                print("LINKING_ERROR")
                sys.exit(1)

if __name__ == "__main__":
    main()
EOF
chmod +x /opt/oracle.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
