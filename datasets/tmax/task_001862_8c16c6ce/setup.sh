#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/algo.py
def longest_path(graph, start_node):
    memo = {}
    def dfs(node):
        if node in memo: 
            return memo[node]
        max_dist = 0
        # BUG: Fails with KeyError if a leaf node is not explicitly listed as a key in the graph dict.
        for neighbor, weight in graph[node]:
            max_dist = max(max_dist, weight + dfs(neighbor))
        memo[node] = max_dist
        return max_dist
    return dfs(start_node)
EOF

    cat << 'EOF' > /home/user/tests.json
[
    {
        "id": 1,
        "graph": {"A": [["B", 2], ["C", 3]], "B": [["C", 1]], "C": []},
        "start": "A",
        "expected": 3
    },
    {
        "id": 2,
        "graph": {"X": [["Y", 5], ["Z", 2]], "Z": [["Y", 10]]},
        "start": "X",
        "expected": 12
    },
    {
        "id": 3,
        "graph": {"M": [["N", 100]]},
        "start": "M",
        "expected": 100
    }
]
EOF

    chmod -R 777 /home/user
