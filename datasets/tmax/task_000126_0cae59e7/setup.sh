#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/graph.json
{
  "nodes": [
    {"id": "Alice", "type": "User"},
    {"id": "Bob", "type": "User"},
    {"id": "Charlie", "type": "User"},
    {"id": "AdminRole", "type": "Role"},
    {"id": "ViewerRole", "type": "Role"},
    {"id": "FinanceDB", "type": "Resource"},
    {"id": "PublicWeb", "type": "Resource"}
  ],
  "edges": [
    {"source": "Alice", "target": "AdminRole", "relation": "HAS_ROLE"},
    {"source": "Bob", "target": "ViewerRole", "relation": "HAS_ROLE"},
    {"source": "AdminRole", "target": "FinanceDB", "relation": "CAN_ACCESS"},
    {"source": "AdminRole", "target": "PublicWeb", "relation": "CAN_ACCESS"},
    {"source": "ViewerRole", "target": "PublicWeb", "relation": "CAN_ACCESS"}
  ]
}
EOF

    sqlite3 /home/user/audit.db << 'EOF'
CREATE TABLE reported_access(user_id TEXT, resource_id TEXT);
INSERT INTO reported_access VALUES ('Alice', 'FinanceDB');
INSERT INTO reported_access VALUES ('Alice', 'PublicWeb');
INSERT INTO reported_access VALUES ('Bob', 'PublicWeb');
INSERT INTO reported_access VALUES ('Bob', 'FinanceDB');
INSERT INTO reported_access VALUES ('Charlie', 'FinanceDB');
INSERT INTO reported_access VALUES ('Charlie', 'PublicWeb');
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
