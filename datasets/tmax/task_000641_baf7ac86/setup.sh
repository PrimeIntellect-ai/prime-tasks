#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq sqlite3 gawk
    pip3 install pytest

    mkdir -p /home/user/compliance_data/

    cat << 'EOF' > /home/user/compliance_data/employees.csv
employee_id,employee_name,role_id
E001,Alice,R1
E002,Bob,R2
E003,Charlie,R3
E004,Diana,R4
E005,Eve,R5
EOF

    cat << 'EOF' > /home/user/compliance_data/roles.json
[
  {"role_id": "R1", "direct_access": ["SYS_A"]},
  {"role_id": "R2", "direct_access": ["SYS_B"]},
  {"role_id": "R3", "direct_access": ["SYS_C"]},
  {"role_id": "R4", "direct_access": ["SYS_D", "SYS_E"]},
  {"role_id": "R5", "direct_access": ["SYS_X"]}
]
EOF

    cat << 'EOF' > /home/user/compliance_data/network_graph.txt
SYS_A SYS_B
SYS_B SYS_X
SYS_B SYS_OMEGA
SYS_C SYS_OMEGA
SYS_D SYS_A
SYS_X SYS_Y
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
