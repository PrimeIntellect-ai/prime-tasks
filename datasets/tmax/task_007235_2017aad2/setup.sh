#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/raw_data/users.csv
id,name,email,age,card
101,Alice Johnson,alice.j@example.com,29,4242-4242-4242-4242
102,Bob Smith,bob@test.com,17,4242-4242-4242-4242
103,Charlie Brown,charlie@domain.com,35,4242-4242-4242-4243
EOF

    cat << 'EOF' > /home/user/raw_data/users.json
[
  {
    "id": 104,
    "name": "Diana Prince",
    "email": "diana.prince@amazon.com",
    "age": 30,
    "card": "4111-1111-1111-1111"
  },
  {
    "id": 105,
    "name": "Eve Adams",
    "email": "eve@eden.com",
    "age": 25,
    "card": "4111-1111-1111-111"
  },
  {
    "id": 106,
    "name": "Frank Castle",
    "email": "frank@punish.org",
    "age": 40,
    "card": "4111111111111111"
  }
]
EOF

    chown -R user:user /home/user/raw_data
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
