#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,name
U73,Alice
U74,Bob
EOF

    cat << 'EOF' > /home/user/user_roles.csv
user_id,role_id
U73,R10
U74,R12
EOF

    cat << 'EOF' > /home/user/roles.json
{
  "R10": ["R11", "R12"],
  "R11": ["R13"],
  "R12": ["R14"],
  "R13": ["R15"],
  "R14": ["R15", "R16"],
  "R15": ["R17"],
  "R17": ["R99"]
}
EOF

    cat << 'EOF' > /home/user/role_resources.csv
role_id,resource_id
R99,RES-999
R16,RES-999
R17,RES-888
EOF

    chmod -R 777 /home/user
