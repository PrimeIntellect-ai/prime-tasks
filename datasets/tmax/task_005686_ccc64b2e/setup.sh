#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets.json
[
  {"id": "D1", "derived_from": [], "schema_fields": ["id", "timestamp", "value", "source"]},
  {"id": "D2", "derived_from": ["D1"], "schema_fields": ["id", "timestamp", "notes"]},
  {"id": "D3", "derived_from": ["D2"], "schema_fields": ["id", "value", "source", "meta"]},
  {"id": "D4", "derived_from": ["D3"], "schema_fields": ["id", "meta", "author"]},
  {"id": "D5", "derived_from": ["D4", "D9"], "schema_fields": ["value", "notes"]},
  {"id": "D6", "derived_from": ["D7"], "schema_fields": ["id", "log"]},
  {"id": "D7", "derived_from": ["D8"], "schema_fields": ["timestamp", "log"]},
  {"id": "D8", "derived_from": ["D6"], "schema_fields": ["id", "source"]},
  {"id": "D9", "derived_from": ["D1"], "schema_fields": ["timestamp", "author"]},
  {"id": "D10", "derived_from": ["D5"], "schema_fields": ["id", "timestamp", "value", "source", "meta"]}
]
EOF

    chmod -R 777 /home/user
