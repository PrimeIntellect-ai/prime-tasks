#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy pyinstaller

mkdir -p /app
cat << 'EOF' > /app/legacy_etl.py
import sys
import datetime
import hashlib
import time

def parse_iso(ts):
    try:
        dt = datetime.datetime.strptime(ts.strip(), '%Y-%m-%dT%H:%M:%SZ')
        minute = (dt.minute // 15) * 15
        dt = dt.replace(minute=minute, second=0, microsecond=0)
        return dt.strftime('%Y-%m-%dT%H:%M:%SZ')
    except:
        return ts

def process():
    window = []
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        parts = line.split(',')
        if len(parts) != 3: continue
        ts, uid, val = parts
        val = float(val)

        aligned = parse_iso(ts)
        masked = hashlib.md5(uid.encode('utf-8')).hexdigest().lower()

        window.append(val)
        if len(window) > 20:
            window.pop(0)

        if len(window) == 1:
            score = 0.0
        else:
            mean = sum(window) / len(window)
            variance = sum((x - mean)**2 for x in window) / (len(window) - 1)
            std = variance ** 0.5
            if std == 0:
                score = 0.0
            else:
                score = (val - mean) / std

        print(f"{aligned},{masked},{score}")

        # Intentional slowdown to simulate a slow legacy process
        time.sleep(0.0002)

if __name__ == '__main__':
    process()
EOF

cd /app
pyinstaller --onefile legacy_etl.py
mv dist/legacy_etl /app/legacy_etl
rm -rf build dist legacy_etl.spec legacy_etl.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
