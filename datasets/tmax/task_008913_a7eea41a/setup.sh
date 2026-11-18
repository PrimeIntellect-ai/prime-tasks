#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/query_plan.json
{
  "nodes": [
    {"id": "op_01", "type": "CollectionScan", "cost": 150},
    {"id": "op_02", "type": "HashMatch", "cost": 450},
    {"id": "op_03", "type": "IndexScan", "cost": 85},
    {"id": "op_04", "type": "CollectionScan", "cost": 210},
    {"id": "op_05", "type": "Sort", "cost": 340},
    {"id": "op_06", "type": "Project", "cost": 120},
    {"id": "op_07", "type": "Filter", "cost": 90},
    {"id": "op_08", "type": "CollectionScan", "cost": 110}
  ],
  "edges": [
    {"source": "op_01", "target": "op_02"},
    {"source": "op_03", "target": "op_02"},
    {"source": "op_04", "target": "op_05"},
    {"source": "op_01", "target": "op_06"},
    {"source": "op_01", "target": "op_05"},
    {"source": "op_08", "target": "op_07"},
    {"source": "op_04", "target": "op_07"},
    {"source": "op_04", "target": "op_02"}
  ]
}
EOF

    chmod -R 777 /home/user
