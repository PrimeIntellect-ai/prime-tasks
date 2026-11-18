#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/dependencies.json
{
  "Frontend": ["API_Gateway"],
  "API_Gateway": ["AuthService", "UserService"],
  "AuthService": ["Database"],
  "UserService": ["Database", "Cache"],
  "Database": [],
  "Cache": [],
  "Logging": [],
  "Metrics": ["Logging"]
}
EOF

cat << 'EOF' > /home/user/service_resolver.py
import json
import resource
import sys
import os

# Set a strict memory limit (approx 120MB) to simulate restricted QA environment limits
# 8 nodes * 10MB = 80MB base. The memory leak easily blows past 120MB.
limit = 120 * 1024 * 1024
resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

class ServiceNode:
    def __init__(self, name):
        self.name = name
        self.dependencies = []
        # Simulate heavy QA environment context initialization
        self._mock_env_data = bytearray(10 * 1024 * 1024)

    def add_dependency(self, node):
        self.dependencies.append(node)

class DependencyGraph:
    def __init__(self):
        self.nodes = {}
        # QA requirement: Keep track of all traversal paths for logging (intentionally flawed in current state)
        self.traversal_paths = []

    def add_node(self, name):
        if name not in self.nodes:
            self.nodes[name] = ServiceNode(name)
        return self.nodes[name]

    def resolve(self):
        visited = set()
        temp_mark = set()
        order = []

        def visit(node_name, path):
            if node_name in temp_mark:
                raise Exception("Cyclic dependency detected")
            if node_name not in visited:
                temp_mark.add(node_name)
                node = self.nodes[node_name]

                # BUG: appending the heavy node object itself into a persistent path history, causing OOM
                new_path = path + [node]
                self.traversal_paths.append(new_path)

                for dep in node.dependencies:
                    visit(dep.name, new_path)

                temp_mark.remove(node_name)
                visited.add(node_name)
                order.append(node_name)

        # Deterministic sorting for deterministic output
        for name in sorted(self.nodes.keys()):
            if name not in visited:
                visit(name, [])

        return order

def main():
    with open('/home/user/dependencies.json') as f:
        data = json.load(f)

    graph = DependencyGraph()
    for srv, deps in data.items():
        node = graph.add_node(srv)
        for dep in deps:
            dep_node = graph.add_node(dep)
            node.add_dependency(dep_node)

    try:
        order = graph.resolve()
        with open('/home/user/execution_order.txt', 'w') as f:
            f.write(",".join(order))
        print("Success: execution_order.txt generated.")
    except MemoryError:
        print("Failed: MemoryError - Script exceeded resource limits.")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

chmod -R 777 /home/user
