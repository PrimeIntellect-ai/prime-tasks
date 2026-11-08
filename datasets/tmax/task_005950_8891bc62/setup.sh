#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl tar gzip ca-certificates golang-go libcurl4 libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.json
[
  {"_id": "E1", "name": "Alice", "managerId": null},
  {"_id": "E2", "name": "Bob", "managerId": "E1"},
  {"_id": "E3", "name": "Charlie", "managerId": "E1"},
  {"_id": "E4", "name": "David", "managerId": "E2"},
  {"_id": "E5", "name": "Eve", "managerId": "E2"},
  {"_id": "E6", "name": "Frank", "managerId": "E3"},
  {"_id": "E7", "name": "Grace", "managerId": "E4"},
  {"_id": "E8", "name": "Heidi", "managerId": "E4"},
  {"_id": "E9", "name": "Ivan", "managerId": "E5"}
]
EOF

    chmod -R 777 /home/user
