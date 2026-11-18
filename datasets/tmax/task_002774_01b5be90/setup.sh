#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest pandas numpy scipy

    mkdir -p /app
    mkdir -p /home/user

    # Create oracle script
    cat << 'EOF' > /app/oracle_process_feed.py
import sys
import re
import pandas as pd
import numpy as np

def main():
    input_text = sys.stdin.read()
    pattern = re.compile(r'\[(\d+)\] METRIC_VAL:\s*([+-]?\d*\.?\d+)')
    matches = pattern.findall(input_text)

    if not matches:
        print("timestamp,value")
        return

    data = [(int(t), float(v)) for t, v in matches]
    df = pd.DataFrame(data, columns=['timestamp', 'value'])
    df = df.sort_values('timestamp').drop_duplicates('timestamp')

    min_t = df['timestamp'].min()
    max_t = df['timestamp'].max()

    full_range = pd.DataFrame({'timestamp': range(min_t, max_t + 1)})
    df = pd.merge(full_range, df, on='timestamp', how='left')
    df['value'] = df['value'].interpolate(method='linear')

    df['value'] = df['value'].round(2)

    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_process_feed.py

    # Create dummy SRT file
    cat << 'EOF' > /tmp/subs.srt
1
00:00:00,000 --> 00:00:00,100
[100] METRIC_VAL: 10.5

2
00:00:00,100 --> 00:00:00,200
[101] METRIC_VAL: 11.0

3
00:00:00,200 --> 00:00:00,300
[104] METRIC_VAL: 12.5

4
00:00:00,300 --> 00:00:00,400
[109] METRIC_VAL: 15.0

5
00:00:00,400 --> 00:00:00,500
[119] METRIC_VAL: 20.0

6
00:00:00,500 --> 00:00:00,600
[121] METRIC_VAL: 21.0

7
00:00:00,600 --> 00:00:00,700
[143] METRIC_VAL: 43.0

8
00:00:00,700 --> 00:00:00,800
[145] METRIC_VAL: 45.0

9
00:00:00,800 --> 00:00:00,900
[150] METRIC_VAL: 50.0
EOF

    # Generate video with embedded subtitles
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=1 -i /tmp/subs.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/instrument_feed.mp4
    rm /tmp/subs.srt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
