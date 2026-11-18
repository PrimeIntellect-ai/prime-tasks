#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest kuzu jsonschema

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
id,name,department
1,Alice,Management
2,Bob,Engineering
3,Charlie,Engineering
4,Diana,Sales
5,Eve,Sales
6,Frank,HR
EOF

    cat << 'EOF' > /home/user/data/edges.csv
src,dst,relationship,weight
1,2,reports_to,0.6
1,3,reports_to,0.8
2,4,colleague,0.7
3,4,colleague,0.4
3,5,colleague,0.9
2,6,colleague,0.2
1,5,reports_to,0.9
5,6,colleague,0.8
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "target_name": { "type": "string" },
      "total_weight": { "type": "number" }
    },
    "required": ["target_name", "total_weight"],
    "additionalProperties": false
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
