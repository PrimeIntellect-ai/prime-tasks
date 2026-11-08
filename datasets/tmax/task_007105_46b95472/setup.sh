#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas duckdb

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/employees.json
[
  {"emp_id": "MGR_042", "name": "Sanctioned Boss", "manager_id": null},
  {"emp_id": "EMP_001", "name": "Alice", "manager_id": "MGR_042"},
  {"emp_id": "EMP_002", "name": "Bob", "manager_id": "MGR_042"},
  {"emp_id": "EMP_003", "name": "Charlie", "manager_id": "EMP_001"},
  {"emp_id": "EMP_004", "name": "Diana", "manager_id": "EMP_001"},
  {"emp_id": "EMP_005", "name": "Eve", "manager_id": "EMP_003"},
  {"emp_id": "EMP_006", "name": "Frank", "manager_id": "MGR_099"},
  {"emp_id": "EMP_007", "name": "Grace", "manager_id": "EMP_006"}
]
EOF

    cat << 'EOF' > /home/user/audit_data/transactions.json
[
  {"tx_id": "T1", "emp_id": "EMP_001", "amount": 1000.0, "status": "COMPLETED"},
  {"tx_id": "T2", "emp_id": "EMP_001", "amount": 500.0, "status": "PENDING"},
  {"tx_id": "T3", "emp_id": "EMP_002", "amount": 3000.0, "status": "COMPLETED"},
  {"tx_id": "T4", "emp_id": "EMP_003", "amount": 4000.0, "status": "COMPLETED"},
  {"tx_id": "T5", "emp_id": "EMP_004", "amount": 50.0, "status": "COMPLETED"},
  {"tx_id": "T6", "emp_id": "EMP_005", "amount": 8000.0, "status": "COMPLETED"},
  {"tx_id": "T7", "emp_id": "EMP_005", "amount": 1000.0, "status": "COMPLETED"},
  {"tx_id": "T8", "emp_id": "MGR_042", "amount": 50000.0, "status": "COMPLETED"},
  {"tx_id": "T9", "emp_id": "EMP_006", "amount": 90000.0, "status": "COMPLETED"}
]
EOF

    chmod -R 777 /home/user
