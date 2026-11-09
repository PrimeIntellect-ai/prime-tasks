#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
id,name,manager_id,dept_id
1,Alice,,1
2,Bob,1,2
3,Charlie,2,2
4,Dave,2,3
5,Eve,3,2
6,Frank,4,3
EOF

    cat << 'EOF' > /home/user/departments.csv
id,name
1,Exec
2,Engineering
3,Sales
EOF

    cat << 'EOF' > /home/user/projects.csv
id,name,dept_id
101,Alpha,2
102,Beta,3
103,Gamma,1
EOF

    cat << 'EOF' > /home/user/assignments.csv
emp_id,project_id
2,101
3,102
4,101
5,101
6,102
2,103
EOF

    chmod -R 777 /home/user
