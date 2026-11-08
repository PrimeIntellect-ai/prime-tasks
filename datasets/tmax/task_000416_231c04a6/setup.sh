#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required Python packages for the task
    pip3 install grpcio grpcio-tools websockets memory_profiler

    # Setup home directory
    mkdir -p /home/user

    # Create the buggy artifact_graph.py
    cat << 'EOF' > /home/user/artifact_graph.py
class Node:
    def __init__(self, name):
        self.name = name
        self.dependencies = []
        self.dependents = [] # Circular reference cause

    def add_dependency(self, node):
        self.dependencies.append(node)
        node.dependents.append(self)

class BuildGraph:
    def __init__(self):
        self.nodes = {}

    def add_artifact(self, name, depends_on):
        if name not in self.nodes:
            self.nodes[name] = Node(name)
        for dep in depends_on:
            if dep not in self.nodes:
                self.nodes[dep] = Node(dep)
            self.nodes[name].add_dependency(self.nodes[dep])

    def get_build_order(self):
        # Topological sort (Kahn's algorithm)
        in_degree = {name: len(node.dependencies) for name, node in self.nodes.items()}
        queue = [name for name, deg in in_degree.items() if deg == 0]
        order = []

        while queue:
            curr = queue.pop(0)
            order.append(curr)
            for dependent in self.nodes[curr].dependents:
                in_degree[dependent.name] -= 1
                if in_degree[dependent.name] == 0:
                    queue.append(dependent.name)

        if len(order) != len(self.nodes):
            return [] # Cycle detected
        return order
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
