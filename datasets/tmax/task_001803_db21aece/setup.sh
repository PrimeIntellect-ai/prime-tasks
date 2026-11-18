#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.csv
user_id,amount
alice,15.10
alice,0.20
bob,10.00
bob,5.30
charlie,7.15
charlie,8.15
EOF

    cat << 'EOF' > /home/user/billing_query.py
import csv
import argparse

def get_users_with_balance(csv_path, target):
    balances = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            user = row['user_id']
            amt = float(row['amount'])
            balances[user] = balances.get(user, 0.0) + amt

    # Query
    results = []
    for user, bal in balances.items():
        if bal == float(target):
            results.append(user)
    return sorted(results)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', type=str, required=True)
    args = parser.parse_args()
    users = get_users_with_balance('/home/user/transactions.csv', args.target)
    print(",".join(users))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
