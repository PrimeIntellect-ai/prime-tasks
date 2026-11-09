#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    # Create hidden python script for the oracle logic
    cat << 'EOF' > /app/.hidden_oracle.py
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if not isinstance(data, list): sys.exit(1)
    for edge in data:
        if not isinstance(edge, dict): sys.exit(1)
        if "src" not in edge or "dst" not in edge or "weight" not in edge: sys.exit(1)
        if not isinstance(edge["src"], str) or "$" in edge["src"]: sys.exit(1)
        if not isinstance(edge["dst"], str) or "$" in edge["dst"]: sys.exit(1)
        if not isinstance(edge["weight"], (int, float)) or edge["weight"] <= 0: sys.exit(1)
    sys.exit(0)
except Exception:
    sys.exit(1)
EOF

    # Create C wrapper to act as a stripped binary
    cat << 'EOF' > /app/graph_oracle.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_oracle.py \"%s\"", argv[1]);
    int ret = system(cmd);
    if (ret != 0) {
        abort();
    }
    return 0;
}
EOF
    gcc -O2 /app/graph_oracle.c -o /app/graph_oracle
    strip /app/graph_oracle
    rm /app/graph_oracle.c

    # Generate clean data
    echo '[{"src": "NodeA", "dst": "NodeB", "weight": 5}]' > /app/data/clean/1.json
    echo '[{"src": "X", "dst": "Y", "weight": 1.5}, {"src": "Y", "dst": "Z", "weight": 10}]' > /app/data/clean/2.json

    # Generate evil data
    echo '{"src": "NodeA", "dst": "NodeB", "weight": 5}' > /app/data/evil/1.json
    echo '[{"src": "NodeA", "weight": 5}]' > /app/data/evil/2.json
    echo '[{"src": "NodeA", "dst": "NodeB", "weight": -2}]' > /app/data/evil/3.json
    echo '[{"src": "Node$A", "dst": "NodeB", "weight": 5}]' > /app/data/evil/4.json
    echo '[{"src": "NodeA", "dst": "NodeB", "weight": "5"}]' > /app/data/evil/5.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
