#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /app/parser.py
import sys
import datetime

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        ts_part, cat, msg = line.split('|', 2)
        year = int(ts_part[0:4])
        day = int(ts_part[5:7])
        month = int(ts_part[8:10])
        hour = int(ts_part[11:13])
        minute = int(ts_part[14:16])
        sec = int(ts_part[17:19])

        dt = datetime.datetime(year, month, day, hour, minute, sec, tzinfo=datetime.timezone.utc)
        epoch = int(dt.timestamp())

        bucket = epoch % 7

        words = msg.split()
        tags = [w for w in words if w.startswith('@')]
        tags.sort()

        tag_str = ",".join(tags) if tags else "NONE"

        print(f"Bucket:{bucket} Epoch:{epoch} Tags:{tag_str} Category:{cat}")
    except Exception as e:
        print("INVALID")
EOF

    cd /app
    pyinstaller --onefile parser.py
    mv dist/parser /app/legacy_parser
    rm -rf build dist parser.py parser.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
