#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/interactions.json
[
  {"protein": "MAPK1", "interacts_with": ["RAF1", "MEK1"]},
  {"protein": "RAF1", "interacts_with": ["MAPK1", "HRAS"]},
  {"protein": "MEK1", "interacts_with": ["MAPK1", "ERK2"]},
  {"protein": "ERK2", "interacts_with": ["MEK1", "MYC", "TP53"]},
  {"protein": "HRAS", "interacts_with": ["RAF1", "PIK3CA"]},
  {"protein": "PIK3CA", "interacts_with": ["HRAS", "AKT1"]},
  {"protein": "AKT1", "interacts_with": ["PIK3CA", "MDM2"]},
  {"protein": "MDM2", "interacts_with": ["AKT1", "TP53"]},
  {"protein": "MYC", "interacts_with": ["ERK2"]},
  {"protein": "TP53", "interacts_with": ["ERK2", "MDM2"]}
]
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "source": { "type": "string" },
    "target": { "type": "string" },
    "path": {
      "type": "array",
      "items": { "type": "string" }
    },
    "distance": { "type": "integer", "minimum": 0 }
  },
  "required": ["source", "target", "path", "distance"],
  "additionalProperties": false
}
EOF

    chmod -R 777 /home/user
