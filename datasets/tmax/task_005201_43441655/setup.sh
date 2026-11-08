#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pillow tzdata

    mkdir -p /app
    mkdir -p /home/user/uptime_repo

    # Create the oracle
    cat << 'EOF' > /app/oracle
#!/usr/bin/env python3
import sys
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

def parse_time(ts_str):
    try:
        parts = ts_str.rsplit(' ', 1)
        if len(parts) != 2:
            return "INVALID"
        dt_str, tz_str = parts
        tz = ZoneInfo(tz_str)
        dt = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S.%f")
        dt = dt.replace(tzinfo=tz, fold=1)
        return f"{dt.timestamp():.6f}"
    except Exception:
        return "INVALID"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("INVALID")
    else:
        print(parse_time(sys.argv[1]))
EOF
    chmod +x /app/oracle

    # Generate the image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (1200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "FATAL: Unhandled format regression. Example: 2023-11-05T01:30:00.123456 America/New_York is failing during the Fall-Back DST overlap. Ensure fold=1 is handled properly for ambiguous times."
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/error_report.png')
EOF
    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    # Setup git repo
    cd /home/user/uptime_repo
    git init
    git config user.name "SRE Admin"
    git config user.email "admin@example.com"

    cat << 'EOF' > parse.py
from datetime import datetime
from zoneinfo import ZoneInfo

def parse(ts_str):
    dt_str, tz_str = ts_str.rsplit(' ', 1)
    tz = ZoneInfo(tz_str)
    dt = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S.%f")
    dt = dt.replace(tzinfo=tz, fold=1)
    return dt.timestamp()
EOF
    git add parse.py
    git commit -m "Initial commit with correct parsing"

    echo "dummy1" > dummy.txt
    git add dummy.txt
    git commit -m "Add dummy file 1"

    cat << 'EOF' > parse.py
from datetime import datetime
from zoneinfo import ZoneInfo

def parse(ts_str):
    dt_str, tz_str = ts_str.rsplit(' ', 1)
    tz = ZoneInfo(tz_str)
    dt = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S.%f")
    dt = dt.replace(tzinfo=tz, fold=0)
    return dt.timestamp()
EOF
    git add parse.py
    git commit -m "Refactor parser, default fold to 0"

    echo "dummy2" > dummy.txt
    git add dummy.txt
    git commit -m "Update dummy file 2"

    echo "dummy3" > dummy.txt
    git add dummy.txt
    git commit -m "Update dummy file 3"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
