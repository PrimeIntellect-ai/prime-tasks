#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,manager_id,name
1,,Alice
2,1,Bob
3,2,Charlie
4,2,Dave
5,1,Eve
6,3,Frank
EOF

    cat << 'EOF' > /home/user/access.json
[
  {"emp_id": 1, "servers": ["RootServer"]},
  {"emp_id": 2, "servers": ["Gateway"]},
  {"emp_id": 3, "servers": ["WebServer"]},
  {"emp_id": 4, "servers": ["Database"]},
  {"emp_id": 5, "servers": ["HRPayroll"]},
  {"emp_id": 6, "servers": ["CacheServer"]}
]
EOF

    cat << 'EOF' > /home/user/network.txt
Gateway WebServer
Gateway Database
WebServer AppServer
Database AppServer
AppServer SecureVault
SecureVault Database
SecureVault BackupServer
Database BackupServer
HRPayroll SecureVault
RootServer Gateway
EOF

    chmod -R 777 /home/user
