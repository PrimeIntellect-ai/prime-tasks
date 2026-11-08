#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y curl build-essential cargo imagemagick tesseract-ocr fonts-dejavu-core

    mkdir -p /app/corpora/clean /app/corpora/evil

    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'ALLOWED_EDGES: CONNECTS, REPLICATES_TO, BACKUP_OF, RESTORES_FROM'" /app/schema_rules.png

    cat << 'EOF' > /app/corpora/clean/valid1.json
[
  {"source": "A", "target": "B", "type": "CONNECTS", "properties": {"post_hook_query": "MATCH (n) RETURN n LIMIT 10"}},
  {"source": "B", "target": "C", "type": "BACKUP_OF", "properties": {"post_hook_query": ""}}
]
EOF

    cat << 'EOF' > /app/corpora/clean/valid2.json
[
  {"source": "DB1", "target": "S3", "type": "BACKUP_OF", "properties": {}},
  {"source": "S3", "target": "ColdStorage", "type": "REPLICATES_TO", "properties": {}}
]
EOF

    cat << 'EOF' > /app/corpora/evil/bad_edge.json
[
  {"source": "A", "target": "B", "type": "HACKS_INTO", "properties": {}}
]
EOF

    cat << 'EOF' > /app/corpora/evil/injection.json
[
  {"source": "A", "target": "B", "type": "CONNECTS", "properties": {"post_hook_query": "MATCH (n) DETACH DELETE n"}}
]
EOF

    cat << 'EOF' > /app/corpora/evil/cycle.json
[
  {"source": "Node1", "target": "Node2", "type": "BACKUP_OF", "properties": {}},
  {"source": "Node2", "target": "Node3", "type": "BACKUP_OF", "properties": {}},
  {"source": "Node3", "target": "Node1", "type": "BACKUP_OF", "properties": {}}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
