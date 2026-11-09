#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import sqlite3
import tempfile

import pytest
import requests

URL = "http://127.0.0.1:8080/api/audit"
HEADERS = {
    "Authorization": "Bearer COMPLIANCE_AUDIT_77x",
    "Content-Type": "application/json",
}


def post_audit(payload):
    try:
        response = requests.post(URL, headers=HEADERS, json=payload, timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert isinstance(data, list), (
        f"Expected response to be a JSON array, got {type(data).__name__}."
    )
    for item in data:
        assert isinstance(item, str), (
            "Expected array elements to be strings (employee IDs), "
            f"got {type(item).__name__}."
        )
    return data


def derive_expected(hr_db, access_logs, comm_graph):
    with sqlite3.connect(hr_db) as connection:
        executives = {
            row[0]
            for row in connection.execute(
                "SELECT id FROM employees WHERE department = ?", ("Executive",)
            )
        }

    with open(access_logs, "r", encoding="utf-8") as handle:
        logs = json.load(handle)
    confidential_readers = {
        record["emp_id"]
        for record in logs
        if record.get("document") == "Confidential_Q4_Earnings"
    }

    with open(comm_graph, "r", encoding="utf-8", newline="") as handle:
        broker_contacts = {
            row["source"]
            for row in csv.DictReader(handle)
            if row.get("target") == "EXT_BROKER_99"
        }

    return executives & confidential_readers & broker_contacts


def create_case(qualifier_count):
    directory = tempfile.mkdtemp(prefix="audit_unseen_")
    hr_db = os.path.join(directory, "unseen_hr.db")
    access_logs = os.path.join(directory, "unseen_access_logs.json")
    comm_graph = os.path.join(directory, "unseen_comm_graph.csv")

    def employee_id(label):
        return f"EMP_{label}_{secrets.token_hex(8).upper()}"

    qualifiers = [employee_id(f"QUAL{i}") for i in range(qualifier_count)]
    wrong_department = employee_id("WRONGDEPT")
    missing_access = employee_id("NOACCESS")
    missing_graph = employee_id("NOGRAPH")
    wrong_document = employee_id("WRONGDOC")
    wrong_target = employee_id("WRONGTARGET")

    employees = [(emp_id, "Executive") for emp_id in qualifiers]
    employees.extend([
        (wrong_department, "Engineering"),
        (missing_access, "Executive"),
        (missing_graph, "Executive"),
        (wrong_document, "Executive"),
        (wrong_target, "Executive"),
    ])

    with sqlite3.connect(hr_db) as connection:
        connection.execute("CREATE TABLE employees (id TEXT, department TEXT)")
        connection.executemany("INSERT INTO employees VALUES (?, ?)", employees)

    logs = [
        {
            "emp_id": emp_id,
            "document": "Confidential_Q4_Earnings",
            "timestamp": "2023-10-15T22:00:00Z",
        }
        for emp_id in qualifiers
    ]
    logs.extend([
        {
            "emp_id": wrong_department,
            "document": "Confidential_Q4_Earnings",
            "timestamp": "2023-10-16T02:30:00Z",
        },
        {
            "emp_id": missing_graph,
            "document": "Confidential_Q4_Earnings",
            "timestamp": "2023-10-16T02:30:00Z",
        },
        {
            "emp_id": wrong_document,
            "document": "Public_Handbook",
            "timestamp": "2023-10-15T22:00:00Z",
        },
        {
            "emp_id": wrong_target,
            "document": "Confidential_Q4_Earnings",
            "timestamp": "2023-10-15T22:00:00Z",
        },
    ])
    with open(access_logs, "w", encoding="utf-8") as handle:
        json.dump(logs, handle)

    edges = [(emp_id, "EXT_BROKER_99") for emp_id in qualifiers]
    edges.extend([
        (wrong_department, "EXT_BROKER_99"),
        (missing_access, "EXT_BROKER_99"),
        (wrong_document, "EXT_BROKER_99"),
        (wrong_target, "INTERNAL_COUNSEL_01"),
    ])
    with open(comm_graph, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source", "target"])
        writer.writerows(edges)

    return {
        "hr_db": hr_db,
        "access_logs": access_logs,
        "comm_graph": comm_graph,
    }


def assert_exact_result(payload):
    expected = derive_expected(
        payload["hr_db"], payload["access_logs"], payload["comm_graph"]
    )
    data = post_audit(payload)
    assert len(data) == len(expected), (
        f"Expected {len(expected)} flagged employees, got {len(data)}. "
        f"Expected IDs: {sorted(expected)}; returned IDs: {data}"
    )
    assert set(data) == expected, (
        f"Incorrect flagged employee IDs. Expected {sorted(expected)}, got {data}"
    )


def test_service_ready_log():
    log_path = "/home/user/service_ready.log"
    assert os.path.exists(log_path), (
        f"Log file {log_path} does not exist. The service might not have started correctly."
    )
    with open(log_path, "r") as handle:
        content = handle.read()
    assert "SERVICE STARTED" in content, (
        f"Log file {log_path} does not contain 'SERVICE STARTED'."
    )


def test_api_audit_endpoint():
    payload = {
        "hr_db": "/data/hr.db",
        "access_logs": "/data/access_logs.json",
        "comm_graph": "/data/comm_graph.csv",
    }
    data = post_audit(payload)

    # Preserve the original seeded-data cardinality assertion.
    assert len(data) == 2, (
        "Expected exactly 2 flagged employees for the default dataset, "
        f"but got {len(data)}. IDs returned: {data}"
    )
    assert set(data) == {"EMP_0042", "EMP_0199"}, (
        f"Incorrect IDs for the default dataset: {data}"
    )


def test_api_uses_unseen_paths_and_computes_ids():
    # Random IDs prevent a fixed response from satisfying the behavioral check.
    assert_exact_result(create_case(2))


def test_api_handles_different_result_cardinality():
    # A second independently generated case ensures the service does not merely
    # return an arbitrary or fixed-size pair of strings.
    assert_exact_result(create_case(1))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
