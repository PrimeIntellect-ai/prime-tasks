#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest pyinstaller

mkdir -p /app
cat << 'EOF' > /app/audit_logic.py
import sys
import json

def main():
    try:
        data = json.load(sys.stdin)
    except:
        return

    nodes = {}
    edges = {}
    grants = {}

    for op in data:
        if op.get('op') == 'add_node':
            nodes[op['node']] = op.get('is_sensitive', False)
        elif op.get('op') == 'add_edge':
            edges.setdefault(op['src'], []).append(op['dst'])
        elif op.get('op') == 'grant':
            grants.setdefault(op['user'], []).append(op['node'])

    res = {}
    for u, starts in grants.items():
        visited = set()
        queue = list(starts)
        while queue:
            curr = queue.pop(0)
            if curr not in visited:
                visited.add(curr)
                queue.extend(edges.get(curr, []))

        count = sum(1 for v in visited if nodes.get(v, False))
        res[u] = count

    print(json.dumps(res, separators=(',', ':'), sort_keys=True))

if __name__ == '__main__':
    main()
EOF

cd /app
pyinstaller --onefile audit_logic.py --distpath /app --name audit_bin
strip /app/audit_bin
rm -rf audit_logic.py build audit_bin.spec

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
