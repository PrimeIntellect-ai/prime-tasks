#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/data/employees.csv
user_id,name,role
u101,Alice Smith,User
u102,Bob Jones,Admin
u103,Charlie Brown,User
u104,Diana Prince,User
EOF

    cat << 'EOF' > /home/user/data/access_logs.json
[
  {"log_id": 1, "user_id": "u101", "entry_node": "A", "target_node": "F", "timestamp": 1672531200},
  {"log_id": 2, "user_id": "u102", "entry_node": "D", "target_node": "F", "timestamp": 1672531500},
  {"log_id": 3, "user_id": "u103", "entry_node": "G", "target_node": "H", "timestamp": 1672531800},
  {"log_id": 4, "user_id": "u104", "entry_node": "E", "target_node": "F", "timestamp": 1672532100}
]
EOF

    cat << 'EOF' > /home/user/data/network.txt
A B
B C
C F
D F
E J
J K
K F
G H
H I
A D
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
