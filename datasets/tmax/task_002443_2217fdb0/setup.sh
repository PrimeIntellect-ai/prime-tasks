#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Generate policy image
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+40 "BACKUP GRAPH POLICY\nAllowed Nodes: Service, Database, Backup\nAllowed Edges: BELONGS_TO, BACKUPS_TO\nRules:\n1. Backup nodes must have retention_days <= 30\n2. A Database backing up to a Backup node in a different region is FORBIDDEN,\nUNLESS the Database belongs to a Service where is_global is true." /app/policy.png

    # Create clean examples
    cat << 'EOF' > /app/clean/clean1.json
{
  "nodes": [
    {"id": 1, "label": "Service", "properties": {"is_global": false}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-east", "retention_days": 14}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    cat << 'EOF' > /app/clean/clean2.json
{
  "nodes": [
    {"id": 1, "label": "Service", "properties": {"is_global": true}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-west", "retention_days": 14}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    cat << 'EOF' > /app/clean/clean3.json
{
  "nodes": [
    {"id": 1, "label": "Service", "properties": {"is_global": false}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-east", "retention_days": 30}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    # Create evil examples
    cat << 'EOF' > /app/evil/evil1.json
{
  "nodes": [
    {"id": 1, "label": "Service", "properties": {"is_global": false}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-west", "retention_days": 14}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    cat << 'EOF' > /app/evil/evil2.json
{
  "nodes": [
    {"id": 1, "label": "Service", "properties": {"is_global": false}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-east", "retention_days": 31}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    cat << 'EOF' > /app/evil/evil3.json
{
  "nodes": [
    {"id": 1, "label": "User", "properties": {"is_global": false}},
    {"id": 2, "label": "Database", "properties": {"region": "us-east"}},
    {"id": 3, "label": "Backup", "properties": {"region": "us-east", "retention_days": 14}}
  ],
  "edges": [
    {"source": 1, "target": 2, "type": "BELONGS_TO"},
    {"source": 2, "target": 3, "type": "BACKUPS_TO"}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
