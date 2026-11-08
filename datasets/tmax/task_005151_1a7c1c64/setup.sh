#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/setup_data.py
import csv
import os

os.makedirs('/home/user/raw_data', exist_ok=True)

employees = [
    (1, 'Alice', 'Engineering'),
    (2, 'Bob', 'Engineering'),
    (3, 'Charlie', 'HR'),
    (4, 'Diana', 'Marketing'),
    (5, 'Eve', 'Executive')
]

with open('/home/user/raw_data/employees.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['emp_id', 'name', 'department'])
    writer.writerows(employees)

messages = [
    (101, 1, 2, '2023-10-01T10:00:00'),
    (102, 2, 3, '2023-10-01T10:05:00'),
    (103, 3, 1, '2023-10-01T10:10:00'), # Triangle 1-2-3
    (104, 1, 2, '2023-10-01T10:15:00'),
    (105, 4, 5, '2023-10-01T11:00:00'),
    (106, 5, 4, '2023-10-01T11:05:00'),
    (107, 2, 4, '2023-10-01T11:10:00'),
    (108, 4, 1, '2023-10-01T11:15:00'),
    (109, 1, 4, '2023-10-01T11:20:00') # Triangle 1-2-4
]

with open('/home/user/raw_data/messages.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['msg_id', 'sender_id', 'receiver_id', 'timestamp'])
    writer.writerows(messages)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
