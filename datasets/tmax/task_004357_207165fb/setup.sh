#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
EOF

cat << 'EOF' > /home/user/purchases.csv
purchase_id,user_id,item
101,1,Laptop
102,1,Mouse
103,2,Keyboard
104,4,Monitor
105,4,Cables
EOF

cat << 'EOF' > /home/user/generate_cypher.py
import csv

users = []
with open('/home/user/users.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        users.append(row)

purchases = []
with open('/home/user/purchases.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        purchases.append(row)

with open('/home/user/relationships.cypher', 'w') as out:
    # BUG: Accidental cross join. No check if u['user_id'] == p['user_id']
    for u in users:
        for p in purchases:
            query = f"MATCH (u:User _LBRACE__LBRACE_user_id: {u['user_id']}_RBRACE__RBRACE_), (p:Purchase _LBRACE__LBRACE_purchase_id: {p['purchase_id']}_RBRACE__RBRACE_) CREATE (u)-[:BOUGHT]->(p);\n"
            out.write(query)
EOF

sed -i 's/_LBRACE_/{/g' /home/user/generate_cypher.py
sed -i 's/_RBRACE_/}/g' /home/user/generate_cypher.py

chmod +x /home/user/generate_cypher.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
