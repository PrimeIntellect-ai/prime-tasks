#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron
    pip3 install pytest

    mkdir -p /app

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
import re
from datetime import datetime

pattern = re.compile(r'^\[(.*?)\] USER=\S+ LANG=\S+ CHANGES=(\d+) KEY=(.*)$')
events = []

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    m = pattern.match(line)
    if m:
        ts_str = m.group(1)
        changes = int(m.group(2))
        key = m.group(3)

        ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S").timestamp()
        events.append((ts, key, changes, ts_str))

        rolling_sum = 0
        for e_ts, e_key, e_changes, _ in events:
            if e_key == key and (ts - 3600) <= e_ts <= ts:
                rolling_sum += e_changes

        print(f"[{ts_str}] KEY={key} ROLLING_CHANGES={rolling_sum}")
EOF
    chmod +x /app/oracle_processor

    # Create video with subtitles
    cat << 'EOF' > /tmp/subs.srt
1
00:00:01,000 --> 00:00:02,000
[2023-10-01 10:00:00] USER=alice LANG=en CHANGES=5 KEY=db_port

2
00:00:03,000 --> 00:00:04,000
[2023-10-01 10:30:00] USER=bob LANG=fr CHANGES=2 KEY=db_port

3
00:00:05,000 --> 00:00:06,000
[2023-10-01 11:05:00] USER=charlie LANG=es CHANGES=10 KEY=db_port

4
00:00:07,000 --> 00:00:08,000
[2023-10-01 11:15:00] USER=alice LANG=en CHANGES=1 KEY=ui_theme
EOF

    ffmpeg -f lavfi -i color=c=black:s=320x240:d=10 -i /tmp/subs.srt -c:v libx264 -c:s mov_text /app/config_changes.mp4
    rm /tmp/subs.srt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
