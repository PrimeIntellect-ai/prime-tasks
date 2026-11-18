#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the video file
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x360:rate=30 -f lavfi -i sine=frequency=1000:duration=5 -c:v libx264 -c:a aac /app/stream.mp4

    # Write the oracle script
    cat << 'EOF' > /app/oracle_reshape.py
#!/usr/bin/env python3
import sys
import csv
import json
from collections import defaultdict

def main():
    reader = csv.DictReader(sys.stdin)
    if not reader.fieldnames:
        print("[]")
        return
    stats = defaultdict(list)
    for row in reader:
        for col in reader.fieldnames:
            if col == 'timestamp':
                continue
            val = row.get(col, '').strip()
            if val:
                try:
                    val_int = int(val)
                    if val_int > 0:
                        stream_type = col.replace('_pkt_size', '')
                        stats[stream_type].append(val_int)
                except ValueError:
                    pass

    result = []
    for stream_type in sorted(stats.keys()):
        sizes = stats[stream_type]
        if sizes:
            max_val = max(sizes)
            avg_val = sum(sizes) / len(sizes)
            result.append({
                "stream_type": stream_type,
                "max": max_val,
                "avg": f"{avg_val:.2f}"
            })

    print(json.dumps(result))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_reshape.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
