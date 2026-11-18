#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # Create config file
    cat << 'EOF' > config.txt
# Module dependencies
app: core, ui, api
core: utils
ui: core, frontend_lib
api: core, backend_url
utils: core
frontend_lib: 
backend_url: http://internal.api/v1
EOF

    # Create database
    sqlite3 metadata.db << 'EOF'
CREATE TABLE owners (
    id INTEGER PRIMARY KEY,
    module_name TEXT,
    owner TEXT,
    active INTEGER
);
INSERT INTO owners (module_name, owner, active) VALUES
('app', 'admin', 1),
('core', 'alice', 0),
('core', 'bob', 1),
('ui', 'charlie', 1),
('api', 'diana', 1),
('api', 'eve', 0),
('utils', 'frank', 1),
('frontend_lib', 'grace', 1),
('backend_url', 'heidi', 1);
EOF

    # Create parser.py
    cat << 'EOF' > parser.py
def parse_config(filepath):
    config = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Bug: Fails if value contains a colon
            k, v = line.split(':')
            config[k.strip()] = v.strip()
    return config
EOF

    # Create resolver.py
    cat << 'EOF' > resolver.py
def resolve_dependencies(start_node, all_edges):
    result = []
    stack = [start_node]
    while stack:
        node = stack.pop()
        if node not in result:
            result.append(node)
        # Bug: pushes children to stack even if already visited, causing infinite loop on cycles
        for child in all_edges.get(node, []):
            stack.append(child)
    return result
EOF

    # Create db_utils.py
    cat << 'EOF' > db_utils.py
import sqlite3

def get_owners(db_path, modules):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    owners = {}
    for mod in modules:
        # Bug: Does not filter correctly
        cur.execute("SELECT owner FROM owners WHERE module_name = ? ORDER BY id ASC", (mod,))
        rows = cur.fetchall()
        if rows:
            # Just grabs the first one
            owners[mod] = rows[0][0]
    return owners
EOF

    # Create build.py
    cat << 'EOF' > build.py
import json
from parser import parse_config
from resolver import resolve_dependencies
from db_utils import get_owners

def main():
    modules_config = parse_config('config.txt')

    edges = {}
    for mod, deps in modules_config.items():
        edges[mod] = [d.strip() for d in deps.split(',') if d.strip()]

    app_deps = resolve_dependencies('app', edges)

    owners = get_owners('metadata.db', app_deps)

    output = {
        "target": "app",
        "dependencies": app_deps,
        "owners": owners
    }

    with open('build_report.json', 'w') as f:
        json.dump(output, f, indent=4)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
