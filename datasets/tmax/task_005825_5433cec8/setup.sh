#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_data.py
import csv

data = [
    ["ID", "Department", "Feedback"],
    ["1", "Sales", "Great work"],
    ["2", "Engineering", "Needs\nimprovement"],
    ["3", "Sales", "Caf\xe9 is nice"],
    ["4", "Sales", "Too many meetings"],
    ["5", "Engineering", "Good"],
    ["6", "Engineering", "Fix the\nbug"]
]

with open('/home/user/input.csv', 'w', newline='', encoding='iso-8859-1') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF
    python3 /home/user/create_data.py

    chmod -R 777 /home/user
