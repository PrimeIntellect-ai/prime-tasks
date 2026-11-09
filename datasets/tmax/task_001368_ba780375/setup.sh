#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data
    cat << 'EOF' > /home/user/audit_data/nodes.json
[
  {"id": "EMP_01", "type": "Employee", "name": "Alice"},
  {"id": "EMP_02", "type": "Employee", "name": "Bob"},
  {"id": "EMP_03", "type": "Employee", "name": "Charlie"},
  {"id": "EMP_04", "type": "Employee", "name": "Diana"},
  {"id": "EMP_05", "type": "Employee", "name": "Eve"},
  {"id": "EMP_06", "type": "Employee", "name": "Frank"},
  {"id": "SYS_001", "type": "System", "name": "Financial_Records"},
  {"id": "SYS_002", "type": "System", "name": "Audit_Logs"},
  {"id": "SYS_003", "type": "System", "name": "General_IT"}
]
EOF

    cat << 'EOF' > /home/user/audit_data/edges.json
[
  {"source": "EMP_01", "target": "EMP_02", "relation": "MANAGES"},
  {"source": "EMP_02", "target": "EMP_03", "relation": "MANAGES"},
  {"source": "EMP_03", "target": "SYS_001", "relation": "HAS_ACCESS"},
  {"source": "EMP_01", "target": "EMP_04", "relation": "MANAGES"},
  {"source": "EMP_04", "target": "SYS_002", "relation": "HAS_ACCESS"},
  {"source": "EMP_05", "target": "SYS_001", "relation": "HAS_ACCESS"},
  {"source": "EMP_05", "target": "SYS_002", "relation": "HAS_ACCESS"},
  {"source": "EMP_06", "target": "SYS_003", "relation": "HAS_ACCESS"}
]
EOF

    chmod -R 777 /home/user
