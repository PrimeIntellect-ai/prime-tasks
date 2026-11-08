#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
from collections import defaultdict

def test_recommendations_accuracy():
    products_path = "/home/user/data/products.csv"
    transactions_path = "/home/user/data/transactions.csv"
    recommendations_path = "/home/user/recommendations.csv"

    assert os.path.isfile(products_path), f"Missing {products_path}"
    assert os.path.isfile(transactions_path), f"Missing {transactions_path}"
    assert os.path.isfile(recommendations_path), f"Missing {recommendations_path} - pipeline did not produce output"

    # 1. Load products
    products = {}
    with open(products_path, "r") as f:
        header = f.readline()
        for line in f:
            if not line.strip(): continue
            pid, cat = line.strip().split(",")
            products[pid] = cat

    # 2. First pass on transactions to get valid amounts per user
    user_valid_amounts = defaultdict(list)
    transactions = []
    with open(transactions_path, "r") as f:
        header = f.readline()
        for line in f:
            if not line.strip(): continue
            parts = line.strip().split(",")
            tx_id, uid, pid = parts[0], parts[1], parts[2]
            amt_str = parts[3] if len(parts) > 3 else ""
            if amt_str:
                amt = int(amt_str)
                user_valid_amounts[uid].append(amt)
                transactions.append((tx_id, uid, pid, amt))
            else:
                transactions.append((tx_id, uid, pid, None))

    # 3. Compute user averages and accumulate spend
    user_category_spend = defaultdict(lambda: defaultdict(int))
    for tx_id, uid, pid, amt in transactions:
        if amt is None:
            if user_valid_amounts[uid]:
                amt = math.floor(sum(user_valid_amounts[uid]) / len(user_valid_amounts[uid]))
            else:
                amt = 0
        cat = products[pid]
        user_category_spend[uid][cat] += amt

    # 4. Determine true top category per user
    truth = {}
    for uid, spends in user_category_spend.items():
        if not spends:
            continue
        top_cat = sorted(spends.items(), key=lambda x: (-x[1], x[0]))[0][0]
        truth[uid] = top_cat

    # 5. Read predictions
    preds = {}
    with open(recommendations_path, "r") as f:
        for line in f:
            if not line.strip(): continue
            parts = line.strip().split(",")
            if len(parts) >= 2:
                uid, cat = parts[0], parts[1]
                preds[uid] = cat

    # 6. Compute accuracy
    correct = 0
    for uid, true_cat in truth.items():
        if preds.get(uid) == true_cat:
            correct += 1

    total = len(truth)
    accuracy = correct / total if total > 0 else 0.0

    assert accuracy >= 0.95, f"Accuracy {accuracy:.4f} is below the 0.95 threshold. Correct: {correct}/{total}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
