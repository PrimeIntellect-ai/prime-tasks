#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/departments.csv
dept_id,dept_name
1,Engineering
2,Sales
3,HR
4,Marketing
5,Executive
EOF

    cat << 'EOF' > /home/user/data/employees.csv
emp_id,name,dept_id
101,Alice,1
102,Bob,1
201,Charlie,2
202,Dave,2
301,Eve,3
401,Frank,4
501,Grace,5
EOF

    cat << 'EOF' > generate_comms.py
import csv

with open('/home/user/data/communications.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['msg_id', 'sender_id', 'receiver_id', 'timestamp'])

    msg_id = 1
    # Eng -> Sales (15)
    for _ in range(10):
        writer.writerow([msg_id, 101, 201, '2023-01-01T10:00:00'])
        msg_id += 1
    for _ in range(5):
        writer.writerow([msg_id, 102, 202, '2023-01-01T10:05:00'])
        msg_id += 1

    # Sales -> HR (20)
    for _ in range(20):
        writer.writerow([msg_id, 201, 301, '2023-01-01T11:00:00'])
        msg_id += 1

    # Exec -> All (8 each)
    for _ in range(8):
        writer.writerow([msg_id, 501, 101, '2023-01-01T12:00:00'])
        msg_id += 1
    for _ in range(8):
        writer.writerow([msg_id, 501, 201, '2023-01-01T12:00:00'])
        msg_id += 1
    for _ in range(8):
        writer.writerow([msg_id, 501, 301, '2023-01-01T12:00:00'])
        msg_id += 1

    # Eng -> Eng (50) - INTRA (should be ignored)
    for _ in range(50):
        writer.writerow([msg_id, 101, 102, '2023-01-01T13:00:00'])
        msg_id += 1
EOF
    python3 generate_comms.py
    rm generate_comms.py

    chmod -R 777 /home/user
