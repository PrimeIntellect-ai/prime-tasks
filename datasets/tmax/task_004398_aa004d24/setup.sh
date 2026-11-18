#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy

    mkdir -p /home/user/networks

    cat << 'EOF' > /home/user/networks/net1.json
{
  "nodes": {
    "G1": {"init": 100.0, "decay": 0.1},
    "G2": {"init": 0.0, "decay": 0.2}
  },
  "edges": [
    {"source": "G1", "target": "G2", "rate": 0.5}
  ]
}
EOF

    cat << 'EOF' > /home/user/networks/net2.json
{
  "nodes": {
    "A": {"init": 50.0, "decay": 0.05},
    "B": {"init": 10.0, "decay": 0.1}
  },
  "edges": [
    {"source": "A", "target": "B", "rate": 0.2}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
