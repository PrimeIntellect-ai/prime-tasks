#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import secrets
import subprocess
import tempfile
import pytest


def compute_expected_csv():
    users_path = "/home/user/users.jsonl"
    orders_path = "/home/user/orders.jsonl"

    if not os.path.exists(users_path) or not os.path.exists(orders_path):
        return ""

    users = {}
    with open(users_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                u = json.loads(line)
                users[u['user_id']] = u.get('region', '')

    totals = {}
    with open(orders_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                o = json.loads(line)
                if o.get('status') == 'completed' and o.get('total', 0) > 100:
                    uid = o['user_id']
                    totals[uid] = totals.get(uid, 0) + o['total']

    results = []
    for uid, total in totals.items():
        results.append((uid, users.get(uid, ""), total))

    # Sort descending by total_spent, then ascending by user_id
    results.sort(key=lambda x: (-x[2], x[0]))

    # Paginate: skip 1, limit 3
    paginated = results[1:4]

    lines = ["user_id,region,total_spent"]
    for r in paginated:
        lines.append(f"{r[0]},{r[1]},{r[2]}")

    return "\n".join(lines)


def test_aggregate_c_exists():
    path = "/home/user/aggregate.c"
    assert os.path.exists(path), f"The C source file {path} is missing."
    assert os.path.isfile(path), f"The path {path} must be a regular file."


def test_results_csv_exists():
    path = "/home/user/results.csv"
    assert os.path.exists(path), f"The output file {path} is missing. Did you compile and run your C program?"
    assert os.path.isfile(path), f"The path {path} must be a regular file."


def test_results_csv_content():
    path = "/home/user/results.csv"
    assert os.path.exists(path), f"Cannot verify content because {path} is missing."

    with open(path, 'r') as f:
        actual_content = f.read().strip()

    expected_content = compute_expected_csv().strip()

    assert expected_content != "", "Could not compute expected CSV because input files are missing or invalid."

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {path} does not match the expected aggregation pipeline output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_compile_and_execute_on_fresh_inputs():
    source_path = "/home/user/aggregate.c"
    users_path = "/home/user/users.jsonl"
    orders_path = "/home/user/orders.jsonl"
    results_path = "/home/user/results.csv"

    with open(users_path, "rb") as f:
        original_users = f.read()
    with open(orders_path, "rb") as f:
        original_orders = f.read()
    with open(results_path, "rb") as f:
        original_results = f.read()

    rng = random.SystemRandom()
    user_ids = [f"U{i}" for i in range(11, 18)]
    regions = ["North", "South", "East", "West", "Central", "Coastal", "Mountain"]
    rng.shuffle(regions)

    users = [
        {"user_id": uid, "name": f"User{i}", "region": regions[i]}
        for i, uid in enumerate(user_ids)
    ]

    assigned_ids = user_ids[:6]
    rng.shuffle(assigned_ids)
    jitter = secrets.randbelow(41)
    targets = [900 + jitter, 800 + jitter, 700 + jitter, 700 + jitter, 500 + jitter, 400 + jitter]

    orders = []
    order_number = 1
    for i, (uid, target) in enumerate(zip(assigned_ids, targets)):
        if i % 2 == 0:
            first = 101 + secrets.randbelow(40)
            orders.append({"order_id": f"T{order_number}", "user_id": uid, "total": first, "status": "completed"})
            order_number += 1
            orders.append({"order_id": f"T{order_number}", "user_id": uid, "total": target - first, "status": "completed"})
            order_number += 1
        else:
            orders.append({"order_id": f"T{order_number}", "user_id": uid, "total": target, "status": "completed"})
            order_number += 1

        # These records must not contribute to the grouped total.
        orders.append({"order_id": f"T{order_number}", "user_id": uid, "total": 100, "status": "completed"})
        order_number += 1
        orders.append({"order_id": f"T{order_number}", "user_id": uid, "total": 999, "status": "pending"})
        order_number += 1

    orders.append({"order_id": f"T{order_number}", "user_id": user_ids[6], "total": 750, "status": "Completed"})
    rng.shuffle(orders)

    try:
        with open(users_path, "w") as f:
            for record in users:
                f.write(json.dumps(record) + "\n")
        with open(orders_path, "w") as f:
            for record in orders:
                f.write(json.dumps(record) + "\n")

        expected_content = compute_expected_csv().strip()
        assert expected_content != "", "Could not compute expected CSV for fresh verification inputs."

        with tempfile.TemporaryDirectory(prefix="aggregate_verify_") as tmpdir:
            executable = os.path.join(tmpdir, "aggregate")
            compile_result = subprocess.run(
                ["gcc", source_path, "-o", executable, "-lcjson"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert compile_result.returncode == 0, (
                "aggregate.c did not compile successfully.\n"
                f"stdout:\n{compile_result.stdout}\n"
                f"stderr:\n{compile_result.stderr}"
            )
            assert os.path.isfile(executable) and os.access(executable, os.X_OK), (
                "Compiling aggregate.c did not produce an executable program."
            )

            if os.path.lexists(results_path):
                os.remove(results_path)

            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert run_result.returncode == 0, (
                "The compiled aggregate program did not run successfully.\n"
                f"stdout:\n{run_result.stdout}\n"
                f"stderr:\n{run_result.stderr}"
            )

        assert os.path.exists(results_path), "The compiled C program did not create /home/user/results.csv."
        assert os.path.isfile(results_path), "/home/user/results.csv must be a regular file."
        with open(results_path, "r") as f:
            actual_content = f.read().strip()

        actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
        expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            "Executing the compiled C program on fresh inputs produced incorrect output.\n"
            f"Expected:\n{chr(10).join(expected_lines)}\n\n"
            f"Actual:\n{chr(10).join(actual_lines)}"
        )
    finally:
        with open(users_path, "wb") as f:
            f.write(original_users)
        with open(orders_path, "wb") as f:
            f.write(original_orders)
        with open(results_path, "wb") as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
