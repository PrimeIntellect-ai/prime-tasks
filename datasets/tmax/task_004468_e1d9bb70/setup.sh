#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install --default-timeout=100 pytest

mkdir -p /app

ffmpeg -f lavfi -i "color=c=gray:s=320x240:d=10" -vf "drawbox=x=0:y=0:w=320:h=240:color=white:t=fill:enable='eq(n,45)+eq(n,120)+eq(n,250)'" -c:v libx264 -y /app/telemetry.mp4

cat << 'EOF' > /app/oracle_detector.py
#!/usr/bin/env python3
import sys
import re

def main():
    history = {}
    anomalies = {}

    line_regex = re.compile(r'^\d+,[A-Za-z]+,\d+(?:\.\d+)?$')

    for line in sys.stdin:
        line = line.strip('\n')
        if not line_regex.match(line):
            sys.stderr.write(f"[ERROR] Invalid line: {line}\n")
            continue

        parts = line.split(',')
        frame = int(parts[0])
        metric = parts[1]
        val = float(parts[2])

        if metric not in history:
            history[metric] = []
            anomalies[metric] = 0

        hist = history[metric]
        is_anomaly = False

        if len(hist) == 3:
            avg = sum(hist) / 3.0
            if abs(val - avg) > 15.0:
                sys.stdout.write(f"ANOMALY at {frame}: {metric} = {val:.2f} (avg = {avg:.2f})\n")
                anomalies[metric] += 1
                is_anomaly = True

        if not is_anomaly:
            hist.append(val)
            if len(hist) > 3:
                hist.pop(0)

    sys.stdout.write("SUMMARY:\n")
    for k in sorted(anomalies.keys()):
        sys.stdout.write(f"{k}: {anomalies[k]}\n")

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_detector.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
