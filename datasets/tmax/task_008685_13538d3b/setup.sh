#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq nodejs
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.json
[
  {"emp_id": 1, "name": "Alice", "manager_id": null},
  {"emp_id": 2, "name": "Bob", "manager_id": 1},
  {"emp_id": 3, "name": "Charlie", "manager_id": 1},
  {"emp_id": 4, "name": "David", "manager_id": 2},
  {"emp_id": 5, "name": "Eve", "manager_id": 2},
  {"emp_id": 6, "name": "Frank", "manager_id": 4},
  {"emp_id": 7, "name": "Grace", "manager_id": 4},
  {"emp_id": 8, "name": "Heidi", "manager_id": 4},
  {"emp_id": 9, "name": "Ivan", "manager_id": 4},
  {"emp_id": 10, "name": "Judy", "manager_id": 3},
  {"emp_id": 11, "name": "Mallory", "manager_id": 3},
  {"emp_id": 12, "name": "Niaj", "manager_id": 3}
]
EOF

    chmod -R 777 /home/user
