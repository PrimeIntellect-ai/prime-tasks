#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/audit_graph.json
{
  "nodes": [
    {"id": "e1", "type": "Employee", "name": "Alice Smith"},
    {"id": "e2", "type": "Employee", "name": "Bob Jones"},
    {"id": "e3", "type": "Employee", "name": "Charlie Brown"},
    {"id": "e4", "type": "Employee", "name": "Dave Wilson"},
    {"id": "e5", "type": "Employee", "name": "Eve Davis"},
    {"id": "d1", "type": "Department", "name": "IT"},
    {"id": "d2", "type": "Department", "name": "HR"},
    {"id": "d3", "type": "Department", "name": "Marketing"},
    {"id": "d4", "type": "Department", "name": "Sales"},
    {"id": "d5", "type": "Department", "name": "Compliance"},
    {"id": "r1", "type": "Role", "name": "System Admin"},
    {"id": "r2", "type": "Role", "name": "HR Rep"},
    {"id": "r3", "type": "Role", "name": "Marketing Analyst"},
    {"id": "r4", "type": "Role", "name": "Sales Executive"},
    {"id": "r5", "type": "Role", "name": "Auditor"},
    {"id": "db1", "type": "Database", "name": "Employee Records", "contains_pii": true},
    {"id": "db2", "type": "Database", "name": "Customer Data", "contains_pii": true},
    {"id": "db3", "type": "Database", "name": "Marketing Leads", "contains_pii": true},
    {"id": "db4", "type": "Database", "name": "Sales Pipeline", "contains_pii": true},
    {"id": "db5", "type": "Database", "name": "Contracts", "contains_pii": true},
    {"id": "db6", "type": "Database", "name": "Public Assets", "contains_pii": false}
  ],
  "edges": [
    {"source": "e1", "target": "d1", "relationship": "WORKS_IN"},
    {"source": "e1", "target": "r1", "relationship": "HAS_ROLE"},
    {"source": "e2", "target": "d2", "relationship": "WORKS_IN"},
    {"source": "e2", "target": "r2", "relationship": "HAS_ROLE"},
    {"source": "e3", "target": "d3", "relationship": "WORKS_IN"},
    {"source": "e3", "target": "r3", "relationship": "HAS_ROLE"},
    {"source": "e4", "target": "d4", "relationship": "WORKS_IN"},
    {"source": "e4", "target": "r4", "relationship": "HAS_ROLE"},
    {"source": "e5", "target": "d5", "relationship": "WORKS_IN"},
    {"source": "e5", "target": "r5", "relationship": "HAS_ROLE"},
    {"source": "r1", "target": "db1", "relationship": "CAN_ACCESS"},
    {"source": "r1", "target": "db2", "relationship": "CAN_ACCESS"},
    {"source": "r2", "target": "db1", "relationship": "CAN_ACCESS"},
    {"source": "r3", "target": "db3", "relationship": "CAN_ACCESS"},
    {"source": "r4", "target": "db2", "relationship": "CAN_ACCESS"},
    {"source": "r4", "target": "db4", "relationship": "CAN_ACCESS"},
    {"source": "r4", "target": "db5", "relationship": "CAN_ACCESS"},
    {"source": "r5", "target": "db1", "relationship": "CAN_ACCESS"},
    {"source": "r5", "target": "db2", "relationship": "CAN_ACCESS"}
  ]
}
EOF

    chmod -R 777 /home/user
