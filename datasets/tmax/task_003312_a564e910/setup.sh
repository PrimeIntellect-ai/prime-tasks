#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema

    mkdir -p /home/user

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "package_name": { "type": "string" },
      "transitive_dependencies": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "package_name": { "type": "string" }
          },
          "required": ["package_name"]
        }
      }
    },
    "required": ["package_name", "transitive_dependencies"]
  }
}
EOF

    cat << 'EOF' > /home/user/mock_output.json
[
  {
    "package_name": "gateway-api",
    "transitive_dependencies": [
      { "package_name": "auth-module", "depends_on": ["crypto-lib"] },
      { "package_name": "crypto-lib", "depends_on": [] }
    ]
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
