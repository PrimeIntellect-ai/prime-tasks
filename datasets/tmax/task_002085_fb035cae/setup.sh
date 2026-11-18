#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/employees.csv
emp_id,name,dept_id,version
1,Alice,10,1
1,Alice,20,2
2,Bob,20,1
3,Charlie,10,1
3,Charlie,30,2
4,Dave,40,1
4,Dave,40,2
EOF

    cat << 'EOF' > /home/user/data/projects.csv
proj_id,proj_name,dept_id,version
101,Project Alpha,10,1
102,Project Beta,20,1
102,Project Beta,20,2
103,Project Gamma,30,1
103,Project Gamma,10,2
104,Project Delta,40,1
EOF

    cat << 'EOF' > /home/user/data/works_on.csv
emp_id,proj_id,version
1,101,1
1,101,2
2,102,1
3,103,1
4,104,1
4,101,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
