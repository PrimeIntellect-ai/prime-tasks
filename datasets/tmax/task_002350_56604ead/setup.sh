#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.py
import sys
import csv
import json
from collections import defaultdict

def main():
    lines = sys.stdin.read().splitlines()
    if not lines:
        print("[]")
        return
    reader = csv.DictReader(lines)

    actor_risk = defaultdict(int)
    target_actors = defaultdict(set)

    for row in reader:
        try:
            score = int(row.get('SeverityScore', 0))
            if score < 5:
                continue
            actor = row['Actor']
            target = row['Target']
            actor_risk[actor] += score
            target_actors[target].add(actor)
        except Exception:
            continue

    vuln_index = {}
    for target, actors in target_actors.items():
        vuln_index[target] = sum(actor_risk[a] for a in actors)

    sorted_targets = sorted(vuln_index.items(), key=lambda x: (-x[1], x[0]))
    top_10 = sorted_targets[:10]

    result = [{"target": t, "vulnerability_index": v} for t, v in top_10]
    print(json.dumps(result, separators=(',', ':')))

if __name__ == '__main__':
    main()
EOF

    cd /tmp
    pyinstaller --onefile legacy.py
    cp dist/legacy /app/legacy_audit_tool
    chmod +x /app/legacy_audit_tool
    rm -rf /tmp/legacy.py /tmp/build /tmp/dist /tmp/legacy.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
