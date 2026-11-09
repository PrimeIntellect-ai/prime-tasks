#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Set up timezone to avoid hangs during apt-get install
    ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
    apt-get update && apt-get install -y tzdata

    apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Create the SLA weights image using ImageMagick
    convert -size 800x100 xc:white -font Liberation-Sans -pointsize 24 -fill black -draw "text 10,50 'Global SLA Weights - us-east: 0.45, eu-west: 0.30, ap-south: 0.25'" /app/sla_weights.png

    # Create reference oracle
    cat << 'EOF' > /app/reference_sla_calc
#!/usr/bin/env python3
import sys
import json
import math
import re

def main():
    data = sys.stdin.read()
    if not data.strip():
        return
    events = json.loads(data)
    weights = {'us-east': 0.45, 'eu-west': 0.30, 'ap-south': 0.25}
    downtimes = []
    for e in events:
        w = weights.get(e.get('region'), 0.0)
        val_str = str(e.get('downtime', '0'))
        # Strip non-numeric characters except for floating point notation
        val_str = re.sub(r'[^\d\.eE+-]', '', val_str)
        try:
            val = float(val_str)
        except ValueError:
            val = 0.0
        downtimes.append(val * w)

    total = math.fsum(downtimes)
    print(f"{total:.8f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/reference_sla_calc

    # Create skeleton buggy script
    cat << 'EOF' > /home/user/fast_sla_calc.py
import sys
import json
import threading

# Broken regional weights
weights = {'us-east': 1.0, 'eu-west': 1.0, 'ap-south': 1.0}

def process_events(events):
    total = 0.0
    lock = threading.Lock()

    def worker(chunk):
        nonlocal total
        # Intentional deadlock bug
        lock.acquire()
        lock.acquire()

        for e in chunk:
            w = weights.get(e['region'], 0.0)
            # Naive float parsing and accumulation
            val = float(e['downtime']) 
            total += val * w

        lock.release()
        lock.release()

    # Split events and run threads (simplified for skeleton)
    threads = []
    chunk_size = max(1, len(events) // 4)
    for i in range(0, len(events), chunk_size):
        t = threading.Thread(target=worker, args=(events[i:i+chunk_size],))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    return total

if __name__ == '__main__':
    data = sys.stdin.read()
    if data.strip():
        events = json.loads(data)
        result = process_events(events)
        print(f"{result:.8f}")
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 755 /app
