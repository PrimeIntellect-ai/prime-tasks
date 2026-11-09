#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph_data.json
{
  "nodes": ["U_105", "Role_A", "Role_B", "Role_C", "Role_D", "Role_E", "R_992", "U_999"],
  "edges": [
    {"source": "U_105", "target": "Role_A", "type": "has_role"},
    {"source": "Role_A", "target": "Role_B", "type": "inherits"},
    {"source": "Role_B", "target": "R_992", "type": "can_read"},
    {"source": "U_105", "target": "Role_C", "type": "has_role"},
    {"source": "Role_C", "target": "Role_D", "type": "inherits"},
    {"source": "Role_D", "target": "Role_E", "type": "inherits"},
    {"source": "Role_E", "target": "R_992", "type": "can_write"},
    {"source": "U_999", "target": "R_992", "type": "can_read"}
  ]
}
EOF

    chmod -R 777 /home/user
