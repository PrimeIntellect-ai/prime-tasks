#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++
    pip3 install pytest

    mkdir -p /home/user
    wget -qO /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    cat << 'EOF' > /home/user/nodes.json
[
  {"id": "Gateway", "load": 10},
  {"id": "Router1", "load": 25},
  {"id": "Router2", "load": 15},
  {"id": "Cache", "load": 30},
  {"id": "Database", "load": 50}
]
EOF

    cat << 'EOF' > /home/user/edges.json
[
  {"src": "Gateway", "dst": "Router1", "latency": 10},
  {"src": "Gateway", "dst": "Router2", "latency": 5},
  {"src": "Router1", "dst": "Database", "latency": 15},
  {"src": "Router2", "dst": "Cache", "latency": 5},
  {"src": "Cache", "dst": "Database", "latency": 20},
  {"src": "Router2", "dst": "Database", "latency": 25}
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
