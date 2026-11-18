#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /app/log_analyzer.py
import sys
import re
import json
import unicodedata

def process():
    data = sys.stdin.read()
    # Tokenize rows handling << >>
    rows = []
    current_row = ""
    in_block = False

    for i in range(len(data)):
        current_row += data[i]
        if data[i:i+2] == '<<':
            in_block = True
        elif data[i:i+2] == '>>':
            in_block = False

        if data[i] == '\n' and not in_block:
            rows.append(current_row[:-1])
            current_row = ""
    if current_row:
        rows.append(current_row)

    sums = {}
    for row in rows:
        cols = row.split('\t')
        if len(cols) != 3:
            continue
        session_id, metadata, metrics = cols
        if not re.match(r'^[A-Za-z0-9]{8}$', session_id):
            continue

        pairs = metrics.split(',')
        for pair in pairs:
            if ':' not in pair:
                continue
            k, v = pair.split(':', 1)
            try:
                val = int(v)
            except ValueError:
                continue

            # Normalize k
            k = unicodedata.normalize('NFKC', k)
            k = k.lower()
            k = re.sub(r'[^a-z0-9\u0080-\uFFFF]', '', k) # simplistic alphanumeric unicode stripping

            if k:
                sums[k] = sums.get(k, 0) + val

    print(json.dumps(sums, separators=(',', ':'), sort_keys=True))

if __name__ == '__main__':
    process()
EOF

    cd /app
    pyinstaller --onefile log_analyzer.py
    mv dist/log_analyzer /app/log_analyzer
    strip /app/log_analyzer
    rm -rf build dist log_analyzer.py log_analyzer.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
