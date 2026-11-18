#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/ticket_8821/data
mkdir -p /home/user/ticket_8821/output

cat << 'EOF' > /home/user/ticket_8821/data/org.json
{
  "1": {"id": "1", "department": "Engineering", "reports": ["2", "3"]},
  "2": {"id": "2", "department": "Engineering", "reports": []},
  "3": {"id": "3", "department": "Engineering", "reports": ["4", "5"]},
  "4": {"id": "4", "department": "Engineering", "reports": ["3"]}, 
  "5": {"id": "5", "reports": ["6"]}, 
  "6": {"id": "6", "department": "Sales", "reports": ["7"]},
  "7": {"id": "7", "department": "Sales", "reports": []},
  "8": {"id": "8", "department": "Marketing", "reports": ["9"]},
  "9": {"id": "9", "department": "Marketing", "reports": ["8"]}
}
EOF

cat << 'EOF' > /home/user/ticket_8821/run.sh
#!/bin/bash
export DATA_DIR="/tmp/wrong_data_path"
python3 /home/user/ticket_8821/process_org.py
EOF
chmod +x /home/user/ticket_8821/run.sh

cat << 'EOF' > /home/user/ticket_8821/process_org.py
import json
import os
import threading
import time

DATA_DIR = os.environ.get("DATA_DIR", "./")
DATA_FILE = os.path.join(DATA_DIR, "org.json")
OUTPUT_FILE = "/home/user/ticket_8821/output/summary.json"

department_counts = {}

def process_employee(data, emp_id):
    emp = data[emp_id]

    # Bug: No corrupted input handling for missing 'department'
    dept = emp["department"]

    # Bug: Race condition
    current = department_counts.get(dept, 0)
    time.sleep(0.001) # Simulate processing time to force race condition
    department_counts[dept] = current + 1

    # Bug: Infinite recursion / no visited set
    for report_id in emp.get("reports", []):
        process_employee(data, report_id)

def main():
    if not os.path.exists(DATA_FILE):
        print(f"Error: {DATA_FILE} not found!")
        exit(1)

    with open(DATA_FILE, 'r') as f:
        data = json.load(f)

    # We simulate multiple workers processing root nodes
    root_nodes = ["1", "6", "8"]
    threads = []

    for root in root_nodes:
        t = threading.Thread(target=process_employee, args=(data, root))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    with open(OUTPUT_FILE, 'w') as f:
        json.dump(department_counts, f)

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
