#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar gawk
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Download and vendor datamash
    mkdir -p /app
    cd /app
    wget https://ftp.gnu.org/gnu/datamash/datamash-1.8.tar.gz
    tar -xzf datamash-1.8.tar.gz
    rm datamash-1.8.tar.gz

    # Inject error at line 2500
    sed -i '2500s/.*/as_fn_error $? "Simulated corruption error" "$LINENO" 5\n&/' /app/datamash-1.8/configure
    chmod -R 777 /app

    # Generate data and evaluator
    cat << 'EOF' > /tmp/setup.py
#!/usr/bin/env python3
import os
import random
from collections import defaultdict
import math

os.makedirs("/home/user/data", exist_ok=True)

# Generate Data
users = list(range(1, 1001))
categories = ["Electronics", "Books", "Clothing", "Home", "Sports"]
products = {}

with open("/home/user/data/products.csv", "w") as f:
    f.write("product_id,category\n")
    for pid in range(1, 101):
        cat = random.choice(categories)
        products[pid] = cat
        f.write(f"{pid},{cat}\n")

with open("/home/user/data/users.csv", "w") as f:
    f.write("user_id,age,region\n")
    for uid in users:
        f.write(f"{uid},{random.randint(18, 70)},Region_{random.randint(1,5)}\n")

# Transactions with missing values
transactions = []
user_valid_amounts = defaultdict(list)

for tx_id in range(1, 5001):
    uid = random.choice(users)
    pid = random.randint(1, 100)
    amt = random.randint(10, 500)
    if random.random() < 0.2:
        # Missing value
        transactions.append((tx_id, uid, pid, None))
    else:
        transactions.append((tx_id, uid, pid, amt))
        user_valid_amounts[uid].append(amt)

with open("/home/user/data/transactions.csv", "w") as f:
    f.write("tx_id,user_id,product_id,amount\n")
    for tx_id, uid, pid, amt in transactions:
        amt_str = str(amt) if amt is not None else ""
        f.write(f"{tx_id},{uid},{pid},{amt_str}\n")

# Generate Ground Truth
user_category_spend = defaultdict(lambda: defaultdict(int))

for tx_id, uid, pid, amt in transactions:
    if amt is None:
        if user_valid_amounts[uid]:
            amt = math.floor(sum(user_valid_amounts[uid]) / len(user_valid_amounts[uid]))
        else:
            amt = 0
    cat = products[pid]
    user_category_spend[uid][cat] += amt

with open("/tmp/reference.csv", "w") as f:
    for uid in sorted(users):
        spends = user_category_spend[uid]
        if not spends:
            continue
        # Sort by spend descending, then category ascending
        top_cat = sorted(spends.items(), key=lambda x: (-x[1], x[0]))[0][0]
        f.write(f"{uid},{top_cat}\n")

# Write Evaluator
evaluator_code = """#!/usr/bin/env python3
import sys

ref = {}
with open("/tmp/reference.csv", "r") as f:
    for line in f:
        uid, cat = line.strip().split(",")
        ref[uid] = cat

pred = {}
try:
    with open("/home/user/recommendations.csv", "r") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            uid, cat = line.split(",")
            pred[uid] = cat
except FileNotFoundError:
    print("metric: 0.0")
    sys.exit(0)

correct = 0
for uid, true_cat in ref.items():
    if pred.get(uid) == true_cat:
        correct += 1

accuracy = correct / len(ref) if ref else 0.0
print(f"metric: {accuracy:.4f}")
"""
with open("/tmp/evaluate.py", "w") as f:
    f.write(evaluator_code)
os.chmod("/tmp/evaluate.py", 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
