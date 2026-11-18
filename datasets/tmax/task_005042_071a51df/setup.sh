#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /app/bkp-graph-1.0.0/src

    cat << 'EOF' > /app/bkp-graph-1.0.0/Makefile
install:
    mkdir -p /home/user/bin /home/user/lib
    cp src/get_chain.py /home/user/lib/
    cp src/get_chain.sh /home/user/bin/
    chmod +x /home/user/bin/get_chain.sh
EOF
    # Convert tabs to spaces if any exist, just to be sure it's spaces
    sed -i 's/\t/    /g' /app/bkp-graph-1.0.0/Makefile

    cat << 'EOF' > /app/bkp-graph-1.0.0/src/get_chain.py
#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    jsonl_file = sys.argv[1]
    target_id = sys.argv[2]

    nodes = {}
    with open(jsonl_file, 'r') as f:
        for line in f:
            if line.strip():
                node = json.loads(line)
                nodes[node['id']] = node

    if target_id not in nodes:
        sys.exit(1)

    chain = []
    curr = target_id
    while curr:
        chain.append(curr)
        node = nodes.get(curr)
        if not node or node.get('type') == 'full':
            break
        curr = node.get('parent_id')

    chain.reverse()
    print(",".join(chain))

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/bkp-graph-1.0.0/src/get_chain.sh
#!/bin/bash
python3 /home/user/lib/get_chain.py "$1" "$2"
EOF

    chmod +x /app/bkp-graph-1.0.0/src/get_chain.py
    chmod +x /app/bkp-graph-1.0.0/src/get_chain.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
