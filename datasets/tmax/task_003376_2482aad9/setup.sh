#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.json
[
  {"id": "u1", "name": "Alice", "dept": "Engineering", "clearance": 3},
  {"id": "u2", "name": "Bob", "dept": "HR", "clearance": 1},
  {"id": "u3", "name": "Charlie", "dept": "Engineering", "clearance": 2},
  {"id": "u4", "name": "Dave", "dept": "Finance", "clearance": 2},
  {"id": "u5", "name": "Eve", "dept": "Legal", "clearance": 5},
  {"id": "u6", "name": "Frank", "dept": "Finance", "clearance": 1}
]
EOF

    cat << 'EOF' > /home/user/org_chart.txt
u1 u3
u4 u2
u5 u4
u4 u6
EOF

    cat << 'EOF' > /home/user/systems.json
{
  "sysA": {"req_dept": "Engineering", "req_clearance": 2},
  "sysB": {"req_dept": "Finance", "req_clearance": 3}
}
EOF

    cat << 'EOF' > /home/user/access_logs.csv
timestamp,user_id,system_id
1620000000,u3,sysA
1620000010,u2,sysA
1620000020,u4,sysB
1620000030,u3,sysB
1620000040,u5,sysB
1620000050,u6,sysB
1620000060,u1,sysB
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
