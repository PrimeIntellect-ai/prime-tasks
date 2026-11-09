#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
from datetime import date, timedelta

import pytest

SCRIPT_PATH = "/home/user/query_engine.sh"
DATA_PATH = "/home/user/data/employees.jsonl"
PROJECTION = {"id", "name", "department", "salary"}


def load_records():
    with open(DATA_PATH, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def expected_results(records, status=None, min_salary=0, sort_by="id", sort_order="asc", skip=0, limit=10):
    selected = [
        record for record in records
        if record["salary"] >= min_salary
        and (status is None or record["status"] == status)
    ]
    selected = sorted(selected, key=lambda record: record[sort_by], reverse=(sort_order == "desc"))
    selected = selected[skip:skip + limit]
    return [
        {
            "id": record["id"],
            "name": record["name"],
            "department": record["department"],
            "salary": record["salary"],
        }
        for record in selected
    ]


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable"


def run_script(args):
    cmd = [SCRIPT_PATH] + args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"

    lines = result.stdout.strip().split('\n')
    if lines == ['']:
        return []

    parsed = []
    for i, line in enumerate(lines):
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Output line {i+1} is not valid JSON: {line}")
    return parsed


def test_specific_test_case():
    args = [
        "--status", "active",
        "--min-salary", "100000",
        "--sort-by", "salary",
        "--sort-order", "desc",
        "--skip", "1",
        "--limit", "2"
    ]
    output = run_script(args)
    assert len(output) == 2, f"Expected 2 results, got {len(output)}"
    expected = [
        {"id": "e04", "name": "Diana", "department": "Engineering", "salary": 130000},
        {"id": "e01", "name": "Alice", "department": "Engineering", "salary": 120000}
    ]
    assert output == expected, f"Expected {expected}, but got {output}"


def test_default_parameters():
    output = run_script([])
    assert len(output) == 10, f"Expected 10 results (default limit), got {len(output)}"
    for record in output:
        assert set(record.keys()) == PROJECTION, "Projection must only include id, name, department, salary"
    ids = [record["id"] for record in output]
    assert ids == sorted(ids), "Default sorting should be by id ascending"
    expected = expected_results(load_records())
    assert output == expected, f"Default query returned incorrect records: {output}"


def test_filter_and_pagination():
    args = [
        "--min-salary", "80000",
        "--skip", "2",
        "--limit", "3"
    ]
    output = run_script(args)
    assert len(output) == 3, f"Expected 3 results, got {len(output)}"
    expected_ids = ["e03", "e04", "e06"]
    actual_ids = [record["id"] for record in output]
    assert actual_ids == expected_ids, f"Expected IDs {expected_ids}, got {actual_ids}"
    expected = expected_results(load_records(), min_salary=80000, skip=2, limit=3)
    assert output == expected, f"Expected {expected}, got {output}"


def make_private_dataset():
    token = secrets.token_hex(6)
    rng = random.SystemRandom()
    salaries = list(range(41003, 41003 + 43 * 173, 173))
    rng.shuffle(salaries)
    records = []
    start = date(2016, 1, 1)
    for i in range(43):
        records.append({
            "id": f"{secrets.token_hex(5)}-{i:02d}",
            "name": f"person-{secrets.token_hex(4)}-{i:02d}",
            "department": f"division-{secrets.token_hex(3)}-{i:02d}",
            "salary": salaries[i],
            "status": f"state-{token}-{i % 3}",
            "join_date": str(start + timedelta(days=i * 29)),
        })
    rng.shuffle(records)
    return records


def invoke_and_compare(records, status=None, min_salary=0, sort_by="id", sort_order="asc", skip=0, limit=10, omit_defaults=False):
    args = []
    if status is not None:
        args += ["--status", status]
    if not omit_defaults or min_salary != 0:
        args += ["--min-salary", str(min_salary)]
    if not omit_defaults or sort_by != "id":
        args += ["--sort-by", sort_by]
    if not omit_defaults or sort_order != "asc":
        args += ["--sort-order", sort_order]
    if not omit_defaults or skip != 0:
        args += ["--skip", str(skip)]
    if not omit_defaults or limit != 10:
        args += ["--limit", str(limit)]

    output = run_script(args)
    expected = expected_results(records, status, min_salary, sort_by, sort_order, skip, limit)
    assert output == expected, f"For arguments {args}, expected {expected}, got {output}"
    for record in output:
        assert set(record.keys()) == PROJECTION, f"Incorrect projection for arguments {args}: {record}"


def test_private_data_and_derived_parameter_combinations():
    original = open(DATA_PATH, "rb").read()
    records = make_private_dataset()
    try:
        with open(DATA_PATH, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, separators=(",", ":")) + "\n")

        # Exercise defaults against data unavailable while the agent was working.
        invoke_and_compare(records, omit_defaults=True)

        statuses = sorted({record["status"] for record in records})
        salaries = sorted(record["salary"] for record in records)
        unique_sort_fields = ["id", "name", "department", "salary", "join_date"]

        # Guaranteed coverage of every meaningful option and both sort orders.
        guaranteed = [
            (statuses[0], salaries[5], "salary", "asc", 0, 11),
            (statuses[1], salaries[12], "salary", "desc", 2, 7),
            (statuses[2], 0, "name", "asc", 1, 9),
            (None, salaries[20], "department", "desc", 3, 8),
            (None, 0, "join_date", "asc", 10, 12),
            ("missing-" + secrets.token_hex(4), 0, "id", "desc", 0, 10),
            (None, salaries[-1] + 1, "id", "asc", 0, 10),
            (None, 0, "salary", "desc", 4, 0),
        ]
        for case in guaranteed:
            invoke_and_compare(records, *case)

        rng = random.SystemRandom()
        status_choices = [None, None] + statuses + ["absent-" + secrets.token_hex(4)]
        minimum_choices = [0, salaries[0], salaries[7], salaries[18], salaries[31], salaries[-1] + 1]
        for _ in range(30):
            invoke_and_compare(
                records,
                status=rng.choice(status_choices),
                min_salary=rng.choice(minimum_choices),
                sort_by=rng.choice(unique_sort_fields),
                sort_order=rng.choice(["asc", "desc"]),
                skip=rng.randrange(0, 16),
                limit=rng.randrange(0, 18),
            )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
