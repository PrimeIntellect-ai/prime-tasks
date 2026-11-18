#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/polybuild/examples

    cat << 'EOF' > /home/user/polybuild/examples/project.poly
target: frontend
version: 1.0.0
depends: api@>=1.10.0, logger@>=2.0.0
---
target: api
version: 1.12.5
depends: database@>=3.5.0
---
target: logger
version: 2.1.0
depends: 
---
target: database
version: 3.6.1
depends: logger@>=1.5.0
EOF

    cat << 'EOF' > /home/user/polybuild/build_parser.py
import sys

def check_version(actual, required):
    # BUG: Naive string comparison
    return actual >= required

def parse_poly_file(filepath):
    targets = {}
    with open(filepath, 'r') as f:
        content = f.read()

    blocks = content.split('---')
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        lines = block.split('\n')
        target_name = ""
        version = ""
        depends = []
        for line in lines:
            line = line.strip()
            if line.startswith("target:"):
                target_name = line.split(":", 1)[1].strip()
            elif line.startswith("version:"):
                version = line.split(":", 1)[1].strip()
            elif line.startswith("depends:"):
                deps_str = line.split(":", 1)[1].strip()
                if deps_str:
                    for d in deps_str.split(','):
                        d = d.strip()
                        if d:
                            depends.append(d)
        if target_name:
            targets[target_name] = {'version': version, 'depends': depends}
    return targets

def get_build_order(targets):
    # Build graph
    graph = {t: [] for t in targets}
    in_degree = {t: 0 for t in targets}

    for t, data in targets.items():
        for dep in data['depends']:
            dep_name, dep_ver = dep.split('@>=')
            if dep_name not in targets:
                raise ValueError(f"Missing dependency: {dep_name}")
            if not check_version(targets[dep_name]['version'], dep_ver):
                raise ValueError(f"Version mismatch for {dep_name}: need >= {dep_ver}, got {targets[dep_name]['version']}")

            # Add edge dep_name -> t
            graph[dep_name].append(t)
            in_degree[t] += 1

    # BUG: Faulty topological sort (uses stack incorrectly, doesn't process all)
    queue = [t for t in targets if in_degree[t] == 0]
    order = []

    while queue:
        node = queue.pop(0)
        order.append(node)
        # BUG: Doesn't decrement in_degree
        for neighbor in graph[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    return order

if __name__ == "__main__":
    if len(sys.argv) > 1:
        t = parse_poly_file(sys.argv[1])
        print(", ".join(get_build_order(t)))
EOF

    touch /home/user/polybuild/test_parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
