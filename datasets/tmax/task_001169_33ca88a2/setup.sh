#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/scheduler_oracle.py
import sys
import json

def get_cumulative_cost(target, manifest, cache):
    if target in cache:
        return cache[target]
    cost = manifest[target]['cost']
    for dep in manifest[target].get('deps', []):
        cost += get_cumulative_cost(dep, manifest, cache)
    cache[target] = cost
    return cost

def main():
    with open(sys.argv[1], 'r') as f:
        manifest = json.load(f)

    # Calculate cumulative costs
    cache = {}
    for target in manifest:
        get_cumulative_cost(target, manifest, cache)

    # Prepare dependencies for toposort-like flattening
    deps_dict = {}
    for target, info in manifest.items():
        deps_dict[target] = set(info.get('deps', []))

    # Implement alphabetical tie-breaking topological sort
    result = []
    while deps_dict:
        # Find nodes with no dependencies
        ready = {node for node, deps in deps_dict.items() if not deps}
        if not ready:
            raise ValueError("Circular dependency")

        # Sort ready alphabetically
        ready_sorted = sorted(ready)

        for node in ready_sorted:
            result.append({"target": node, "cumulative_cost": cache[node]})
            del deps_dict[node]
            # Remove this node from other dependencies
            for other_deps in deps_dict.values():
                other_deps.discard(node)

    print(json.dumps(result))

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/scheduler_oracle.py

    # Setup vendored package perturbation
    mkdir -p /app/toposort-1.10
    pip3 install toposort==1.10 -t /app/toposort-1.10

    # Apply the perturbation
    sed -i 's/def toposort_flatten(data, sort=True):/def toposort_flatten(data, sort=True)/g' /app/toposort-1.10/toposort.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
