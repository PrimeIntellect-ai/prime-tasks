#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.py
import sys
import csv
import json

def main():
    if len(sys.argv) < 2:
        return
    with open(sys.argv[1], 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    for r in rows:
        r['txn_id'] = int(r['txn_id'])
        r['user_id'] = int(r['user_id'])
        r['timestamp'] = int(r['timestamp'])
        r['amount'] = float(r['amount'])
    out = []
    for a in rows:
        s = 0.0
        for b in rows:
            if b['user_id'] == a['user_id'] and b['timestamp'] <= a['timestamp']:
                s += b['amount']
        score = round(a['amount'] * s, 2)
        out.append({'txn_id': a['txn_id'], 'anomalous_score': score})
    out.sort(key=lambda x: x['txn_id'])
    print(json.dumps(out))

if __name__ == '__main__':
    main()
EOF

    cd /tmp
    pyinstaller --onefile legacy.py --distpath /app --name legacy_reporter
    strip /app/legacy_reporter
    cd /
    rm -rf /tmp/legacy* /tmp/build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
