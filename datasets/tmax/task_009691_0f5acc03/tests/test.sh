#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re


def test_script_exists_and_executable():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_output_file_exists():
    output_path = '/home/user/user_features.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."


def test_output_content_matches_expected():
    output_path = '/home/user/user_features.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    users = {}
    with open('/home/user/data/users.csv', 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[row['user_id']] = {
                'total_net_spend': 0.0,
                'max_days_active': 1,
                'has_orders': False
            }

    returns = {}
    with open('/home/user/data/returns.csv', 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            returns[row['order_id']] = float(row['return_amount'])

    with open('/home/user/data/orders.csv', 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_id = row['user_id']
            if user_id not in users:
                continue

            order_id = row['order_id']
            order_amount = float(row['order_amount'])
            days_active = int(row['days_active'])
            ret_amount = returns.get(order_id, 0.0)
            net_spend = order_amount - ret_amount

            users[user_id]['total_net_spend'] += net_spend
            if not users[user_id]['has_orders']:
                users[user_id]['max_days_active'] = days_active
                users[user_id]['has_orders'] = True
            elif days_active > users[user_id]['max_days_active']:
                users[user_id]['max_days_active'] = days_active

    expected_rows = []
    for user_id in sorted(users.keys(), key=lambda x: int(x)):
        u = users[user_id]
        tns = u['total_net_spend']
        mda = u['max_days_active']
        ltv = round(tns + (tns / mda) * 30, 2)

        if ltv >= 500.00:
            segment = 'VIP'
        elif ltv >= 100.00:
            segment = 'Standard'
        else:
            segment = 'Churn_Risk'

        expected_rows.append({
            'user_id': user_id,
            'total_net_spend': round(tns, 2),
            'max_days_active': mda,
            'predicted_LTV': ltv,
            'segment': segment
        })

    actual_rows = []
    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        expected_header = ['user_id', 'total_net_spend', 'max_days_active', 'predicted_LTV', 'segment']
        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

        for row in reader:
            assert len(row) == 5, f"Row has incorrect number of columns: {row}"
            assert re.fullmatch(r'-?(?:0|[1-9][0-9]*)\.[0-9]{2}', row[3]), \
                f"predicted_LTV must have exactly two decimal places, got {row[3]!r}"
            actual_rows.append({
                'user_id': row[0],
                'total_net_spend': float(row[1]),
                'max_days_active': int(float(row[2])),
                'predicted_LTV': float(row[3]),
                'segment': row[4]
            })

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}"

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert expected['user_id'] == actual['user_id'], f"Row {i}: user_id mismatch. Expected {expected['user_id']}, got {actual['user_id']}"
        assert math.isclose(expected['total_net_spend'], actual['total_net_spend'], abs_tol=0.01), f"Row {i}: total_net_spend mismatch for user {expected['user_id']}. Expected {expected['total_net_spend']}, got {actual['total_net_spend']}"
        assert expected['max_days_active'] == actual['max_days_active'], f"Row {i}: max_days_active mismatch for user {expected['user_id']}. Expected {expected['max_days_active']}, got {actual['max_days_active']}"
        assert math.isclose(expected['predicted_LTV'], actual['predicted_LTV'], abs_tol=0.01), f"Row {i}: predicted_LTV mismatch for user {expected['user_id']}. Expected {expected['predicted_LTV']}, got {actual['predicted_LTV']}"
        assert expected['segment'] == actual['segment'], f"Row {i}: segment mismatch for user {expected['user_id']}. Expected {expected['segment']}, got {actual['segment']}"
TEST_EOF

tmpdir=$(mktemp -d)
cp /home/user/data/users.csv "$tmpdir/users.original.csv"
cp /home/user/data/orders.csv "$tmpdir/orders.original.csv"
cp /home/user/data/returns.csv "$tmpdir/returns.original.csv"
overall=1

run_and_verify() {
    baseline_dir="$1"
    rm -f /home/user/user_features.csv

    if ! (cd /home/user && timeout 30s ./run_pipeline.sh); then
        overall=0
    fi

    if ! cmp -s /home/user/data/users.csv "$baseline_dir/users.csv" || \
       ! cmp -s /home/user/data/orders.csv "$baseline_dir/orders.csv" || \
       ! cmp -s /home/user/data/returns.csv "$baseline_dir/returns.csv"; then
        overall=0
        cp "$baseline_dir/users.csv" /home/user/data/users.csv
        cp "$baseline_dir/orders.csv" /home/user/data/orders.csv
        cp "$baseline_dir/returns.csv" /home/user/data/returns.csv
    fi

    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        overall=0
    fi
}

mkdir "$tmpdir/original"
cp "$tmpdir/users.original.csv" "$tmpdir/original/users.csv"
cp "$tmpdir/orders.original.csv" "$tmpdir/original/orders.csv"
cp "$tmpdir/returns.original.csv" "$tmpdir/original/returns.csv"
run_and_verify "$tmpdir/original"
if [ -f /home/user/user_features.csv ]; then
    cp /home/user/user_features.csv "$tmpdir/original_generated.csv"
fi

cat > /home/user/data/users.csv <<'EOF'
user_id,age_group,region
8,26-35,North
2,18-25,West
15,36-50,South
4,26-35,East
EOF
cat > /home/user/data/orders.csv <<'EOF'
order_id,user_id,order_amount,days_active
201,2,100.00,10
202,2,50.00,20
203,8,300.00,30
204,15,20.00,10
EOF
cat > /home/user/data/returns.csv <<'EOF'
order_id,return_amount
201,25.00
204,15.00
EOF

mkdir "$tmpdir/fixture"
cp /home/user/data/users.csv "$tmpdir/fixture/users.csv"
cp /home/user/data/orders.csv "$tmpdir/fixture/orders.csv"
cp /home/user/data/returns.csv "$tmpdir/fixture/returns.csv"
run_and_verify "$tmpdir/fixture"

cp "$tmpdir/users.original.csv" /home/user/data/users.csv
cp "$tmpdir/orders.original.csv" /home/user/data/orders.csv
cp "$tmpdir/returns.original.csv" /home/user/data/returns.csv
if [ -f "$tmpdir/original_generated.csv" ]; then
    cp "$tmpdir/original_generated.csv" /home/user/user_features.csv
else
    rm -f /home/user/user_features.csv
fi
rm -rf "$tmpdir"

if [ "$overall" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
