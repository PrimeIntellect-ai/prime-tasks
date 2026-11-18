#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph_data.jsonl
{"type": "node", "id": "res1", "label": "Resource", "name": "customer_pii_db"}
{"type": "node", "id": "res2", "label": "Resource", "name": "public_web"}
{"type": "node", "id": "r_admin", "label": "Role", "name": "Admin"}
{"type": "node", "id": "r_dev", "label": "Role", "name": "Developer"}
{"type": "node", "id": "r_lead", "label": "Role", "name": "Lead"}
{"type": "node", "id": "r_intern", "label": "Role", "name": "Intern"}
{"type": "node", "id": "u1", "label": "User", "name": "Alice"}
{"type": "node", "id": "u2", "label": "User", "name": "Bob"}
{"type": "node", "id": "u3", "label": "User", "name": "Charlie"}
{"type": "node", "id": "u4", "label": "User", "name": "Dave"}
{"type": "edge", "from": "r_admin", "to": "res1", "relation": "CAN_ACCESS"}
{"type": "edge", "from": "r_admin", "to": "res2", "relation": "CAN_ACCESS"}
{"type": "edge", "from": "r_dev", "to": "res2", "relation": "CAN_ACCESS"}
{"type": "edge", "from": "r_lead", "to": "r_admin", "relation": "INHERITS"}
{"type": "edge", "from": "u1", "to": "r_admin", "relation": "HAS_ROLE"}
{"type": "edge", "from": "u2", "to": "r_dev", "relation": "HAS_ROLE"}
{"type": "edge", "from": "u3", "to": "r_lead", "relation": "HAS_ROLE"}
{"type": "edge", "from": "u4", "to": "r_intern", "relation": "HAS_ROLE"}
EOF

    chmod -R 777 /home/user
