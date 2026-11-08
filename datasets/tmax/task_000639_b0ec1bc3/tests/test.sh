#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from datetime import datetime, timedelta
import pytest

def get_expected_influencers():
    products_path = '/home/user/data/products.csv'
    orders_path = '/home/user/data/orders.csv'
    order_items_path = '/home/user/data/order_items.csv'

    products = {}
    with open(products_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            products[row['product_id']] = row['category']

    orders = {}
    with open(orders_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            orders[row['order_id']] = {
                'user_id': int(row['user_id']),
                'order_date': datetime.strptime(row['order_date'], '%Y-%m-%d').date()
            }

    user_category_dates = []
    with open(order_items_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            order_id = row['order_id']
            product_id = row['product_id']
            if order_id in orders and product_id in products:
                user_id = orders[order_id]['user_id']
                date = orders[order_id]['order_date']
                category = products[product_id]
                user_category_dates.append((user_id, category, date))

    influencers = set()
    for u1, c1, d1 in user_category_dates:
        subsequent_users = set()
        for u2, c2, d2 in user_category_dates:
            if c1 == c2 and u1 != u2:
                if timedelta(days=1) <= (d2 - d1) <= timedelta(days=7):
                    subsequent_users.add(u2)
        if len(subsequent_users) >= 3:
            influencers.add(u1)

    return sorted(list(influencers))

def test_influencers_file_exists():
    file_path = "/home/user/influencers.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

def test_influencers_file_format_and_content():
    file_path = "/home/user/influencers.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert isinstance(data, list), f"JSON content must be a list, but got {type(data).__name__}."
    assert all(isinstance(x, int) for x in data), "All elements in the JSON list must be integers."

    expected_influencers = get_expected_influencers()

    assert data == sorted(data), "The list of influencer user_ids is not sorted in ascending order."
    assert data == expected_influencers, f"Expected influencers {expected_influencers}, but got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
