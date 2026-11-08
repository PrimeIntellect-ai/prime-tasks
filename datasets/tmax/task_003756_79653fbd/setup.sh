#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/data/nodes.json
[
  {"id": "A", "delay": 2},
  {"id": "B", "delay": 5},
  {"id": "C", "delay": 1},
  {"id": "D", "delay": 0},
  {"id": "E", "delay": 3},
  {"id": "F", "delay": 10}
]
EOF

    cat << 'EOF' > /home/user/data/edges.json
[
  {"source": "A", "target": "B", "cost": 10},
  {"source": "A", "target": "C", "cost": 2},
  {"source": "C", "target": "B", "cost": 3},
  {"source": "B", "target": "D", "cost": 5},
  {"source": "C", "target": "D", "cost": 12},
  {"source": "D", "target": "E", "cost": 2},
  {"source": "E", "target": "F", "cost": 1},
  {"source": "C", "target": "F", "cost": 20}
]
EOF

    cat << 'EOF' > /home/user/data/queries.json
[
  {"query_id": "q1", "start": "A", "end": "E"},
  {"query_id": "q2", "start": "A", "end": "F"},
  {"query_id": "q3", "start": "C", "end": "D"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
