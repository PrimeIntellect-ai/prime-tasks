#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/subs.srt
1
00:00:00,000 --> 00:00:05,000
CHUNK_SIZE=3
ENCODING=iso-8859-1
EOF
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -i /tmp/subs.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/archive_feed.mp4

    cat << 'EOF' > /app/oracle_converter.py
import sys
import json
import csv
import io

def main():
    input_data = sys.stdin.read().strip()
    if not input_data:
        records = []
    else:
        records = json.loads(input_data)

    chunk_size = 3
    encoding = 'iso-8859-1'

    output_str = ""
    header = ["filename", "size_bytes", "checksum"]

    if not records:
        f = io.StringIO()
        writer = csv.writer(f)
        writer.writerow(header)
        output_str = f.getvalue()
    else:
        chunks = [records[i:i + chunk_size] for i in range(0, len(records), chunk_size)]

        chunk_strings = []
        for chunk in chunks:
            f = io.StringIO()
            writer = csv.writer(f)
            writer.writerow(header)
            for rec in chunk:
                writer.writerow([rec['filename'], rec['size_bytes'], rec['checksum']])
            chunk_strings.append(f.getvalue().strip() + "\n")

        output_str = "---SPLIT---\n".join(chunk_strings)

    # convert string to bytes and write to stdout
    sys.stdout.buffer.write(output_str.encode(encoding))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
