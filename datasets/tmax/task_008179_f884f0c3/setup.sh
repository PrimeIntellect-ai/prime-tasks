#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deps.json
{
  "app": {"data": "app_data_v1", "deps": ["libA", "libB"]},
  "libA": {"data": "libA_data_v2", "deps": ["libC"]},
  "libB": {"data": "libB_data_v1", "deps": ["libC", "libD"]},
  "libC": {"data": "libC_data_v3", "deps": ["libE"]},
  "libD": {"data": "libD_data_v1", "deps": ["libE"]},
  "libE": {"data": "libE_data_v2", "deps": []}
}
EOF

    cat << 'EOF' > /home/user/dep_resolver.py
import json
import hashlib

class DepGraph:
    def __init__(self):
        self.nodes = {}

    def add_node(self, name, data, deps):
        self.nodes[name] = {'data': data, 'deps': deps}

    def resolve(self, target):
        visited = set()
        resolved = []

        def visit(node):
            if node in visited:
                return
            visited.add(node)
            if node not in self.nodes:
                raise StandardError("Missing dependency: " + node)

            deps = self.nodes[node]['deps']
            deps.sort()
            for dep in deps:
                visit(dep)

            resolved.append(node)

        visit(target)
        return resolved

    def compute_checksum(self, target):
        order = self.resolve(target)
        checksums = {}

        for node in order:
            m = hashlib.md5()
            m.update(self.nodes[node]['data'])
            for dep in sorted(self.nodes[node]['deps']):
                m.update(checksums[dep])
            checksums[node] = m.hexdigest()

        return checksums[target]

if __name__ == "__main__":
    with open("/home/user/deps.json", "r") as f:
        data = json.load(f)

    graph = DepGraph()
    for k, v in data.items():
        graph.add_node(k, v['data'], v['deps'])

    try:
        ans = graph.compute_checksum("app")
        print "Checksum for app:", ans
        with open("/home/user/checksum.txt", "w") as out:
            out.write(ans + "\n")
    except Exception, e:
        print "Error:", e
EOF

    chmod -R 777 /home/user
