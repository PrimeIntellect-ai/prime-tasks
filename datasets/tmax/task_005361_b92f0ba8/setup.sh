#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/libA.json
{
  "name": "libA",
  "schema_version": 2,
  "provides": ["A"],
  "requires": []
}
EOF

    cat << 'EOF' > /home/user/artifacts/libB.json
{
  "name": "libB",
  "schema_version": 1,
  "provides": ["B"],
  "needs": ["A"]
}
EOF

    cat << 'EOF' > /home/user/artifacts/libC.json
{
  "name": "libC",
  "schema_version": 2,
  "provides": ["C"],
  "requires": ["B", "D"]
}
EOF

    cat << 'EOF' > /home/user/artifacts/libD.json
{
  "name": "libD",
  "schema_version": 2,
  "provides": ["D"],
  "requires": ["C"]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
