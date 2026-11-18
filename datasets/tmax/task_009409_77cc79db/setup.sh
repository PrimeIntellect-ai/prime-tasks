#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,department
1,Alice,Sales
2,Bob,Sales
3,Charlie,Engineering
4,David,Engineering
5,Eve,Engineering
6,Frank,HR
7,Grace,HR
EOF

    cat << 'EOF' > /home/user/interactions.csv
source_id,target_id,timestamp,interaction_type
1,2,2023-01-01T10:00:00,email
2,1,2023-01-01T10:05:00,email
1,3,2023-01-01T11:00:00,meeting
3,4,2023-01-01T12:00:00,email
4,5,2023-01-01T13:00:00,meeting
5,3,2023-01-01T14:00:00,email
6,1,2023-01-01T15:00:00,meeting
99,1,2023-01-01T16:00:00,email
3,99,2023-01-01T17:00:00,email
3,6,2023-01-01T18:00:00,meeting
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
