#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc binutils
    pip3 install pytest pyinstaller

    # Install Rust globally
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ln -s /opt/cargo/bin/* /usr/local/bin/
    chmod -R 777 /opt/cargo /opt/rustup

    # Create the oracle python script
    cat << 'EOF' > /tmp/oracle.py
import sys
import json
import heapq

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    source = sys.argv[1]
    target = sys.argv[2]

    data = sys.stdin.read()
    try:
        graph = json.loads(data)
    except Exception:
        sys.exit(1)

    queue = [(0, source, [source])]
    visited = set()

    while queue:
        cost, current, path = heapq.heappop(queue)
        if current in visited:
            continue
        visited.add(current)

        if current == target:
            print(f"Optimal derivation: {' -> '.join(path)} (Cost: {cost})")
            return

        if current in graph and "deps" in graph[current]:
            for nxt, weight in graph[current]["deps"].items():
                if nxt not in visited:
                    heapq.heappush(queue, (cost + weight, nxt, path + [nxt]))

    print("Unreachable")

if __name__ == "__main__":
    main()
EOF

    # Compile the oracle binary
    pyinstaller --onefile /tmp/oracle.py
    mkdir -p /app
    cp dist/oracle /app/dataset_lineage_oracle
    chmod +x /app/dataset_lineage_oracle
    strip /app/dataset_lineage_oracle

    # Cleanup
    rm -rf /tmp/oracle.py build dist oracle.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
