#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/dummy.srt
1
00:00:01,000 --> 00:00:02,000
Hello World
EOF

    ffmpeg -f lavfi -i color=c=black:s=320x240:d=3 -i /tmp/dummy.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/reference_video.mp4
    rm /tmp/dummy.srt

    mkdir -p /opt/verifier
    cat << 'EOF' > /opt/verifier/oracle_parser.py
import sys
import re

def main():
    pattern = re.compile(r'^(\d{2}:\d{2}:\d{2}\.\d{3}) - <([A-Z0-9]{2,10})> : (.*)$')
    for line in sys.stdin:
        line = line.rstrip('\n')
        match = pattern.match(line)
        if match:
            time_val, speaker, text = match.groups()
            print(f'<trans unit="{speaker}" time="{time_val}">{text}</trans>')
        else:
            print('<error>MALFORMED</error>')

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
