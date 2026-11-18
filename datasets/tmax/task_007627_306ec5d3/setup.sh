#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl
    pip3 install --default-timeout=100 pytest

    # Setup directories
    mkdir -p /home/user/data
    mkdir -p /home/user/include

    # Download JSON library for C++
    curl -sL https://raw.githubusercontent.com/nlohmann/json/v3.11.2/single_include/nlohmann/json.hpp -o /home/user/include/json.hpp

    # Create relational data
    cat << 'EOF' > /home/user/data/users.csv
U1,Alice,Engineering
U2,Bob,Engineering
U3,Charlie,Engineering
U4,Diana,Marketing
U5,Eve,Marketing
U6,Frank,HR
EOF

    # Create document data
    cat << 'EOF' > /home/user/data/permissions.json
[
  {"uid": "U1", "roles": ["admin", "deploy"]},
  {"uid": "U2", "roles": ["read", "write"]},
  {"uid": "U3", "roles": ["read"]},
  {"uid": "U4", "roles": ["social", "analytics"]},
  {"uid": "U5", "roles": ["content"]},
  {"uid": "U6", "roles": ["onboarding"]}
]
EOF

    # Create graph data
    cat << 'EOF' > /home/user/data/reports_to.txt
U1:U2,U3
U4:U5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
