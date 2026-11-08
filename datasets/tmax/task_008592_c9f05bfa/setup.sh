#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,manager_id,name
EXEC-1,,Boss
MGR-042,EXEC-1,Suspect
EMP-101,MGR-042,Alice
EMP-102,MGR-042,Bob
EMP-201,EMP-101,Charlie
EMP-202,EMP-102,David
EMP-301,EXEC-1,Eve
EMP-302,EMP-301,Frank
EOF

    cat << 'EOF' > /home/user/access_logs.json
[
  {"emp_id": "MGR-042", "system_name": "Vault", "access_time": "2023-10-01T10:00:00Z"},
  {"emp_id": "EMP-101", "system_name": "CRM", "access_time": "2023-10-02T09:15:00Z"},
  {"emp_id": "EMP-101", "system_name": "Vault", "access_time": "2023-10-03T11:00:00Z"},
  {"emp_id": "EMP-201", "system_name": "CRM", "access_time": "2023-10-04T14:30:00Z"},
  {"emp_id": "EMP-202", "system_name": "HR_Portal", "access_time": "2023-10-05T08:00:00Z"},
  {"emp_id": "EMP-301", "system_name": "Vault", "access_time": "2023-10-06T10:00:00Z"},
  {"emp_id": "EMP-302", "system_name": "CRM", "access_time": "2023-10-07T09:00:00Z"},
  {"emp_id": "MGR-042", "system_name": "CRM", "access_time": "2023-10-08T16:45:00Z"}
]
EOF

    chmod -R 777 /home/user
