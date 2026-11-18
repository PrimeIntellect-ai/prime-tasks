#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /setup.py
import csv
import os

emp_file = '/home/user/employees.csv'
comm_file = '/home/user/communications.csv'

# Create employees
employees = [
    ("E001", "Alice", "Executive"),
    ("E002", "Charlie", "HR"),
    ("E005", "David", "Engineering"),
    ("E006", "Eve", "Marketing"),
    ("E007", "Frank", "Engineering"),
    ("E008", "Grace", "Engineering"),
    ("E009", "Heidi", "Support"),
    ("E012", "Bob", "Engineering"),
    ("E015", "Ivan", "Sales")
]

with open(emp_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["emp_id", "name", "department"])
    writer.writerows(employees)

comms = [
    ("E001", "E002", 5),
    ("E005", "E001", 12),
    ("E005", "E006", 3),
    ("E007", "E005", 8),
    ("E005", "E008", 22),
    ("E008", "E009", 1),
    ("E012", "E008", 7),
    ("E002", "E015", 4)
]

with open(comm_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["sender_id", "receiver_id", "message_count"])
    writer.writerows(comms)
EOF

    python3 /setup.py
    rm /setup.py

    chmod -R 777 /home/user
