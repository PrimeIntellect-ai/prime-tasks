#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libc-bin coreutils
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/dag.py
def resolve_dependencies(graph):
    """
    Resolves dependencies and returns a valid execution order.
    graph: dict mapping a node to a list of its dependencies.
    """
    result = []
    visited = set()

    def dfs(node):
        if node in visited:
            return
        for dep in graph.get(node, []):
            dfs(dep)
        visited.add(node)
        result.append(node)

    for n in graph:
        dfs(n)
    return result
EOF

    cat << 'EOF' > /home/user/project/test_dag.py
from dag import resolve_dependencies
import pytest

def test_linear():
    graph = {'A': ['B'], 'B': ['C'], 'C': []}
    assert resolve_dependencies(graph) == ['C', 'B', 'A']

def test_diamond():
    # A depends on B and C, which both depend on D
    graph = {'A': ['B', 'C'], 'B': ['D'], 'C': ['D'], 'D': []}
    result = resolve_dependencies(graph)
    assert result.index('D') < result.index('B')
    assert result.index('D') < result.index('C')
    assert result.index('B') < result.index('A')
    assert result.index('C') < result.index('A')

def test_cycle():
    graph = {'A': ['B'], 'B': ['C'], 'C': ['A']}
    with pytest.raises(ValueError, match="Cycle detected"):
        resolve_dependencies(graph)
EOF

    cat << 'EOF' > /tmp/update.patch
--- dag.py
+++ dag.py
@@ -5,14 +5,18 @@
     """
     result = []
     visited = set()
+    visiting = set()

     def dfs(node):
+        if node in visiting:
+            raise ValueError("Cycle detected")
         if node in visited:
             return
+        visiting.add(node)
         for dep in graph.get(node, []):
             dfs(dep)
         visited.add(node)
         result.append(node)

     for n in graph:
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/update.patch | base64 > /home/user/pr_submission.b64

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
