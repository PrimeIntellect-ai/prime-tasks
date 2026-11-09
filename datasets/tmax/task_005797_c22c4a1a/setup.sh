#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 << 'EOF'
import os
import json

base_dir = '/home/user/project_logs'
os.makedirs(base_dir, exist_ok=True)

modules = {
    'auth': {'lines': 250, 'chunk_size': 100},
    'payment': {'lines': 120, 'chunk_size': 50},
    'inventory': {'lines': 400, 'chunk_size': 500},
    'notifications': {'lines': 30, 'chunk_size': 10}
}

for mod, data in modules.items():
    mod_dir = os.path.join(base_dir, mod)
    os.makedirs(mod_dir, exist_ok=True)

    # Create settings.xml
    with open(os.path.join(mod_dir, 'settings.xml'), 'w') as f:
        f.write('<?xml version="1.0"?>\n<config>\n  <chunk_lines>' + str(data["chunk_size"]) + '</chunk_lines>\n</config>')

    # Create data.jsonl
    with open(os.path.join(mod_dir, 'data.jsonl'), 'w') as f:
        for i in range(data['lines']):
            f.write(json.dumps({"id": i, "module": mod, "status": "ok"}) + '\n')
EOF

    chmod -R 777 /home/user
