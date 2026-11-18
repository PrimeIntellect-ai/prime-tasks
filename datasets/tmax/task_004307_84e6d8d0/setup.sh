#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/employees.csv
emp_id,full_name,department
101,Alice Smith,Engineering
102,Bob Jones,HR
103,Charlie Brown,Engineering
104,Diana Prince,Management
105,Evan Wright,Sales
EOF

    cat << 'EOF' > /home/user/data/messages.csv
msg_id,sender_emp_id,receiver_emp_id,bytes,timestamp
1,101,103,500,2023-10-01T10:00:00Z
2,101,104,1500,2023-10-01T10:05:00Z
3,102,101,200,2023-10-01T10:10:00Z
4,103,104,800,2023-10-01T10:15:00Z
5,105,104,3000,2023-10-01T10:20:00Z
6,104,101,100,2023-10-01T10:25:00Z
7,101,103,250,2023-10-01T10:30:00Z
8,105,101,400,2023-10-01T10:35:00Z
EOF

    chmod -R 777 /home/user
