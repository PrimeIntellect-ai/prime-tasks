#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/deps.json
{
  "main": ["ui", "engine"],
  "ui": ["render", "utils"],
  "engine": ["physics", "render"],
  "physics": ["math", "utils"],
  "render": ["math"],
  "math": [],
  "utils": []
}
EOF

    cat << 'EOF' > /home/user/project/costs.json
{
  "main": 5,
  "ui": 10,
  "engine": 15,
  "physics": 20,
  "render": 12,
  "math": 8,
  "utils": 3
}
EOF

    cat << 'EOF' > /home/user/project/resolver.py
import json

def load_data():
    with open('/home/user/project/deps.json') as f:
        deps = json.load(f)
    with open('/home/user/project/costs.json') as f:
        costs = json.load(f)
    return deps, costs

def get_build_order(deps):
    # BUGGY IMPLEMENTATION: just returns alphabetical keys
    return sorted(list(deps.keys()))

def get_critical_path(deps, costs):
    # NOT IMPLEMENTED
    return 0

if __name__ == "__main__":
    deps, costs = load_data()
    order = get_build_order(deps)
    cp = get_critical_path(deps, costs)

    with open('/home/user/build_order.txt', 'w') as f:
        f.write(",".join(order))

    with open('/home/user/critical_path.txt', 'w') as f:
        f.write(str(cp))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
