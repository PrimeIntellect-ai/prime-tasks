#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/bin

    # Generate the reference video quickly using ultrafast preset
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=6 -r 30 \
      -vf "drawbox=x=0:y=0:w=10:h=10:color=white:t=fill:enable='between(n,15,30)+eq(n,88)+between(n,105,140)'" \
      -c:v libx264 -preset ultrafast -y /app/reference_run.mp4

    # Create oracle processor
    cat << 'EOF' > /app/bin/oracle_processor
#!/usr/bin/env python3
import sys
import json

def process(input_str):
    if not input_str.strip():
        return "[]"
    lines = input_str.strip().split('\n')
    frames = set()
    for line in lines:
        if line.strip().isdigit():
            frames.add(int(line.strip()))

    sorted_frames = sorted(list(frames))
    if not sorted_frames:
        return "[]"

    events = []
    start = sorted_frames[0]
    prev = sorted_frames[0]

    for f in sorted_frames[1:]:
        if f == prev + 1:
            prev = f
        else:
            events.append({"start": start, "end": prev})
            start = f
            prev = f
    events.append({"start": start, "end": prev})

    return json.dumps(events, separators=(',', ':'))

if __name__ == "__main__":
    print(process(sys.stdin.read()))
EOF
    chmod +x /app/bin/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
