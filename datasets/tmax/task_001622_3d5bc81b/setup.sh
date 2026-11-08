#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyinstaller

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy_parser.py
#!/usr/bin/env python3
import sys
import csv
import json
from decimal import Decimal, ROUND_HALF_UP
from collections import defaultdict

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    nodes = {}
    with open(sys.argv[1], 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            emp_id = int(row[0])
            manager_id = int(row[1]) if row[1].strip() else None
            department = row[2]
            score = float(row[3])
            nodes[emp_id] = {
                'emp_id': emp_id,
                'manager_id': manager_id,
                'department': department,
                'score': score,
                'chain_length': 0
            }

    for emp_id in nodes:
        length = 0
        curr = nodes[emp_id]['manager_id']
        while curr is not None:
            length += 1
            curr = nodes[curr]['manager_id'] if curr in nodes else None
        nodes[emp_id]['chain_length'] = length

    groups = defaultdict(list)
    for emp_id, data in nodes.items():
        groups[(data['department'], data['chain_length'])].append(data['score'])

    averages = {}
    for k, v in groups.items():
        avg = sum(Decimal(str(x)) for x in v) / Decimal(len(v))
        averages[k] = float(avg.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))

    result = []
    for emp_id in sorted(nodes.keys()):
        data = nodes[emp_id]
        result.append({
            "emp_id": emp_id,
            "chain_length": data['chain_length'],
            "dept_peer_avg": averages[(data['department'], data['chain_length'])]
        })

    print(json.dumps(result))

if __name__ == '__main__':
    main()
EOF

    pyinstaller --onefile /tmp/legacy_parser.py --distpath /app --name legacy_parser
    chmod +x /app/legacy_parser
    rm -rf /tmp/legacy_parser.py /build /legacy_parser.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
