#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from collections import defaultdict

import pytest

SCRIPT = "/home/user/audit_pipeline.py"
OUTPUT = "/home/user/flagged_audit.json"
EMP_FILE = "/home/user/audit_data/employees.json"
TX_FILE = "/home/user/audit_data/transactions.json"


def recompute_expected(employees, transactions, target_mgr):
    manager_to_direct_reports = defaultdict(list)
    for emp in employees:
        mgr = emp.get("manager_id")
        if mgr:
            manager_to_direct_reports[mgr].append(emp.get("emp_id"))

    downstream_emps = set()
    queue = manager_to_direct_reports[target_mgr].copy()
    while queue:
        current = queue.pop(0)
        if current in downstream_emps:
            continue
        downstream_emps.add(current)
        queue.extend(manager_to_direct_reports[current])

    emp_totals = defaultdict(float)
    for tx in transactions:
        if tx.get("status") == "COMPLETED" and tx.get("emp_id") in downstream_emps:
            emp_totals[tx["emp_id"]] += float(tx["amount"])

    sorted_totals = sorted(emp_totals.items(), key=lambda x: x[1], reverse=True)
    return [{"emp_id": emp_id, "total_amount": amt} for emp_id, amt in sorted_totals[:3]]


def run_pipeline(target):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT, target],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Pipeline failed for target {target}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT), f"Pipeline did not create {OUTPUT} for target {target}."
    try:
        with open(OUTPUT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Pipeline wrote invalid JSON for target {target}: {exc}")


def test_audit_pipeline_script_exists():
    assert os.path.isfile(SCRIPT), "/home/user/audit_pipeline.py does not exist."


def test_pipeline_execution_parameterization_and_aggregation():
    token = secrets.token_hex(6)
    mgr_a = f"MGR_A_{token}"
    mgr_b = f"MGR_B_{token}"
    a1, a2, a3, a4, a5 = [f"A{i}_{token}" for i in range(1, 6)]
    b1, b2 = [f"B{i}_{token}" for i in range(1, 3)]
    outsider = f"OUT_{token}"

    employees = [
        {"emp_id": mgr_a, "name": "Manager A", "manager_id": None},
        {"emp_id": a1, "name": "A1", "manager_id": mgr_a},
        {"emp_id": a2, "name": "A2", "manager_id": mgr_a},
        {"emp_id": a3, "name": "A3", "manager_id": a1},
        {"emp_id": a4, "name": "A4", "manager_id": a3},
        {"emp_id": a5, "name": "A5", "manager_id": a2},
        {"emp_id": mgr_b, "name": "Manager B", "manager_id": None},
        {"emp_id": b1, "name": "B1", "manager_id": mgr_b},
        {"emp_id": b2, "name": "B2", "manager_id": b1},
        {"emp_id": outsider, "name": "Outsider", "manager_id": None},
    ]
    transactions = [
        {"tx_id": f"T1_{token}", "emp_id": a1, "amount": 110.25, "status": "COMPLETED"},
        {"tx_id": f"T2_{token}", "emp_id": a1, "amount": 99999.0, "status": "PENDING"},
        {"tx_id": f"T3_{token}", "emp_id": a2, "amount": 420.5, "status": "COMPLETED"},
        {"tx_id": f"T4_{token}", "emp_id": a3, "amount": 300.0, "status": "COMPLETED"},
        {"tx_id": f"T5_{token}", "emp_id": a3, "amount": 350.75, "status": "COMPLETED"},
        {"tx_id": f"T6_{token}", "emp_id": a4, "amount": 925.0, "status": "COMPLETED"},
        {"tx_id": f"T7_{token}", "emp_id": a5, "amount": 275.0, "status": "COMPLETED"},
        {"tx_id": f"T8_{token}", "emp_id": mgr_a, "amount": 500000.0, "status": "COMPLETED"},
        {"tx_id": f"T9_{token}", "emp_id": b1, "amount": 7100.0, "status": "COMPLETED"},
        {"tx_id": f"T10_{token}", "emp_id": b2, "amount": 8200.5, "status": "COMPLETED"},
        {"tx_id": f"T11_{token}", "emp_id": outsider, "amount": 900000.0, "status": "COMPLETED"},
    ]

    with open(EMP_FILE, "rb") as f:
        original_employees = f.read()
    with open(TX_FILE, "rb") as f:
        original_transactions = f.read()

    actual_a = actual_b = None
    try:
        with open(EMP_FILE, "w") as f:
            json.dump(employees, f)
        with open(TX_FILE, "w") as f:
            json.dump(transactions, f)

        actual_a = run_pipeline(mgr_a)
        actual_b = run_pipeline(mgr_b)
    finally:
        with open(EMP_FILE, "wb") as f:
            f.write(original_employees)
        with open(TX_FILE, "wb") as f:
            f.write(original_transactions)
        run_pipeline("MGR_042")

    assert actual_a == recompute_expected(employees, transactions, mgr_a), (
        "Pipeline output was incorrect for the first parameterized manager."
    )
    assert actual_b == recompute_expected(employees, transactions, mgr_b), (
        "Pipeline output was incorrect for the second parameterized manager."
    )


def test_flagged_audit_output():
    output_file = "/home/user/flagged_audit.json"
    assert os.path.isfile(output_file), f"{output_file} does not exist. Did you run the script?"

    with open(output_file, "r") as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} is not valid JSON.")

    emp_file = "/home/user/audit_data/employees.json"
    tx_file = "/home/user/audit_data/transactions.json"

    assert os.path.isfile(emp_file), f"Source file {emp_file} is missing."
    assert os.path.isfile(tx_file), f"Source file {tx_file} is missing."

    with open(emp_file, "r") as f:
        employees = json.load(f)

    with open(tx_file, "r") as f:
        transactions = json.load(f)

    manager_to_direct_reports = defaultdict(list)
    for emp in employees:
        mgr = emp.get("manager_id")
        if mgr:
            manager_to_direct_reports[mgr].append(emp.get("emp_id"))

    target_mgr = "MGR_042"
    downstream_emps = set()
    queue = manager_to_direct_reports[target_mgr].copy()

    while queue:
        current = queue.pop(0)
        downstream_emps.add(current)
        queue.extend(manager_to_direct_reports[current])

    emp_totals = defaultdict(float)
    for tx in transactions:
        if tx.get("status") == "COMPLETED" and tx.get("emp_id") in downstream_emps:
            emp_totals[tx["emp_id"]] += float(tx["amount"])

    sorted_totals = sorted(emp_totals.items(), key=lambda x: x[1], reverse=True)
    top_3 = sorted_totals[:3]

    expected_output = [{"emp_id": emp_id, "total_amount": amt} for emp_id, amt in top_3]

    assert isinstance(output_data, list), f"Expected output to be a JSON array, got {type(output_data).__name__}."
    assert len(output_data) == len(expected_output), f"Expected {len(expected_output)} records, got {len(output_data)}."

    for i, (actual, expected) in enumerate(zip(output_data, expected_output)):
        assert actual.get("emp_id") == expected["emp_id"], f"Record {i+1}: expected emp_id '{expected['emp_id']}', got '{actual.get('emp_id')}'."
        assert actual.get("total_amount") == expected["total_amount"], f"Record {i+1}: expected total_amount {expected['total_amount']}, got {actual.get('total_amount')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
