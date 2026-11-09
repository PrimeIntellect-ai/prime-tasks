#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cd /home/user/data

    cat << 'EOF' > generate_data.py
import csv
import random

random.seed(42)

persons = [{"id": i, "name": f"Person_{i}"} for i in range(1, 101)]
companies = [{"id": i, "name": f"Company_{chr(64+i) if i <= 26 else 'Z'+str(i)}"} for i in range(1, 51)]

board_members = []
investments = []

# Generate board memberships
for p in persons:
    # Each person is on 1 to 3 boards
    num_boards = random.randint(1, 3)
    comps = random.sample(companies, num_boards)
    for c in comps:
        board_members.append({"person_id": p["id"], "company_id": c["id"]})

# Generate investments
for _ in range(200):
    c1, c2 = random.sample(companies, 2)
    investments.append({"investor_company_id": c1["id"], "target_company_id": c2["id"], "amount": random.randint(100, 10000) * 1000})

# Force a few specific conflicts of interest
# Conflict 1: Person 10 is on board of Company 5 and Company 10. Company 5 invested in 10.
board_members.extend([{"person_id": 10, "company_id": 5}, {"person_id": 10, "company_id": 10}])
investments.append({"investor_company_id": 5, "target_company_id": 10, "amount": 500000})

# Conflict 2: Person 88 on board of 12 and 33. 33 invested in 12.
board_members.extend([{"person_id": 88, "company_id": 12}, {"person_id": 88, "company_id": 33}])
investments.append({"investor_company_id": 33, "target_company_id": 12, "amount": 750000})

# De-duplicate
board_members = [dict(t) for t in {tuple(d.items()) for d in board_members}]
investments = [dict(t) for t in {tuple(d.items()) for d in investments}]

def write_csv(filename, fieldnames, data):
    with open(filename, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)

write_csv('persons.csv', ['id', 'name'], persons)
write_csv('companies.csv', ['id', 'name'], companies)
write_csv('board_members.csv', ['person_id', 'company_id'], board_members)
write_csv('investments.csv', ['investor_company_id', 'target_company_id', 'amount'], investments)
EOF

    python3 generate_data.py
    rm generate_data.py

    chmod -R 777 /home/user
