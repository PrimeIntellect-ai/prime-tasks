#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the sample video (1280x720, 30fps, 10s = 300 frames)
    ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 -pix_fmt yuv420p /app/archive_sample.mp4

    # Create the reference oracle
    cat << 'EOF' > /app/reference_oracle_segment_sizer
#!/usr/bin/env python3
import sys
import json

def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    print("start,end,bytes")
    for item in data:
        start = item["start_frame"]
        end = item["end_frame"]
        size = (end - start + 1) * 2764800
        print(f"{start},{end},{size}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/reference_oracle_segment_sizer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
