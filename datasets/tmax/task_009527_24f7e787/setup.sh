#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/lineage.json
[
  {"source": "DS_A", "target": "DS_B"},
  {"source": "DS_B", "target": "DS_C"},
  {"source": "DS_C", "target": "DS_A"},
  {"source": "DS_C", "target": "DS_X"},
  {"source": "DS_X", "target": "DS_Y"},
  {"source": "DS_D", "target": "DS_E"},
  {"source": "DS_E", "target": "DS_F"},
  {"source": "DS_F", "target": "DS_G"},
  {"source": "DS_G", "target": "DS_E"},
  {"source": "DS_H", "target": "DS_I"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
