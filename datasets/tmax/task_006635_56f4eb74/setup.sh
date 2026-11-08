#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph.json
{
  "nodes": [
    {"id": "E1", "label": "Employee", "name": "Alice"},
    {"id": "E2", "label": "Employee", "name": "Bob"},
    {"id": "E3", "label": "Employee", "name": "Charlie"},
    {"id": "E4", "label": "Employee", "name": "Diana"},
    {"id": "E5", "label": "Employee", "name": "Eve"},
    {"id": "R1", "label": "Role", "name": "Admin"},
    {"id": "R2", "label": "Role", "name": "User"},
    {"id": "R3", "label": "Role", "name": "Manager"},
    {"id": "R4", "label": "Role", "name": "Auditor"},
    {"id": "S1", "label": "System", "name": "FinancialDB", "sensitivity": "HIGH"},
    {"id": "S2", "label": "System", "name": "HR_Portal", "sensitivity": "HIGH"},
    {"id": "S3", "label": "System", "name": "PublicSite", "sensitivity": "LOW"},
    {"id": "S4", "label": "System", "name": "CustomerData", "sensitivity": "HIGH"},
    {"id": "S5", "label": "System", "name": "LogServer", "sensitivity": "HIGH"}
  ],
  "edges": [
    {"source": "E1", "target": "R1", "type": "HAS_ROLE"},
    {"source": "E1", "target": "R2", "type": "HAS_ROLE"},
    {"source": "E2", "target": "R2", "type": "HAS_ROLE"},
    {"source": "E3", "target": "R3", "type": "HAS_ROLE"},
    {"source": "E4", "target": "R4", "type": "HAS_ROLE"},
    {"source": "E5", "target": "R1", "type": "HAS_ROLE"},
    {"source": "R1", "target": "S1", "type": "HAS_ACCESS"},
    {"source": "R1", "target": "S2", "type": "HAS_ACCESS"},
    {"source": "R1", "target": "S4", "type": "HAS_ACCESS"},
    {"source": "R1", "target": "S5", "type": "HAS_ACCESS"},
    {"source": "R2", "target": "S3", "type": "HAS_ACCESS"},
    {"source": "R3", "target": "S2", "type": "HAS_ACCESS"},
    {"source": "R4", "target": "S5", "type": "HAS_ACCESS"}
  ]
}
EOF

    cat << 'EOF' > /home/user/audit.py
import json

with open('/home/user/graph.json') as f:
    data = json.load(f)

employees = [n for n in data['nodes'] if n['label'] == 'Employee']
roles = [n for n in data['nodes'] if n['label'] == 'Role']
systems = [n for n in data['nodes'] if n['label'] == 'System' and n.get('sensitivity') == 'HIGH']

results = []
# BUG: implicit cross join ignoring edges!
for e in employees:
    for r in roles:
        for s in systems:
            results.append({"employee": e['name'], "system": s['name']})

with open('/home/user/audit_results.json', 'w') as f:
    json.dump(results[:5], f, indent=2)
EOF

    chmod -R 777 /home/user
