#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/extract_hierarchy.sh"
DB_PATH = "/home/user/company.db"


def test_script_exists_and_executable():
    """Test that the extract_hierarchy.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable."


def run_script_and_parse_json(*args):
    """Helper to run the script and parse its stdout as JSON."""
    result = subprocess.run(
        [SCRIPT_PATH] + [str(a) for a in args],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        pytest.fail(
            f"Script output is not valid JSON. Output was:\n{result.stdout}\nError: {e}"
        )

    return data


def test_extract_hierarchy_case_1():
    """Test the script with MANAGER_ID=2, MIN_SALARY=90000, LIMIT=3."""
    data = run_script_and_parse_json(2, 90000, 3)

    expected = [
        {"id": 2, "name": "VP Eng", "salary": 150000},
        {"id": 4, "name": "Director Eng", "salary": 120000},
        {"id": 5, "name": "Eng Manager", "salary": 100000},
    ]

    assert data == expected, f"Expected {expected}, but got {data}"


def test_extract_hierarchy_case_2():
    """Test the script with MANAGER_ID=5, MIN_SALARY=60000, LIMIT=10."""
    data = run_script_and_parse_json(5, 60000, 10)

    expected = [
        {"id": 5, "name": "Eng Manager", "salary": 100000},
        {"id": 6, "name": "Senior Eng 1", "salary": 95000},
        {"id": 7, "name": "Senior Eng 2", "salary": 95000},
        {"id": 8, "name": "Junior Eng 1", "salary": 70000},
        {"id": 9, "name": "Junior Eng 2", "salary": 65000},
    ]

    assert data == expected, f"Expected {expected}, but got {data}"


def test_extract_hierarchy_empty_result():
    """Test the script with a high minimum salary that yields no results."""
    data = run_script_and_parse_json(5, 200000, 10)
    assert data == [], f"Expected empty list [], but got {data}"


def test_is_bash_script_with_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, "Artifact must be a Bash script"
    non_comment_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", non_comment_source, re.IGNORECASE), (
        "Script must contain a recursive SQL CTE"
    )
    assert DB_PATH in source, f"Script must connect to {DB_PATH}"


def expected_result(rows, manager_id, min_salary, limit):
    by_id = {row[0]: row for row in rows}
    if manager_id not in by_id:
        return []

    children = {}
    for row in rows:
        children.setdefault(row[2], []).append(row[0])

    subtree = set()
    pending = [manager_id]
    while pending:
        employee_id = pending.pop()
        if employee_id in subtree:
            continue
        subtree.add(employee_id)
        pending.extend(children.get(employee_id, []))

    selected = [
        row for row in rows if row[0] in subtree and row[3] >= min_salary
    ]
    selected.sort(key=lambda row: (-row[3], row[0]))
    selected = selected[:limit]
    return [
        {"id": row[0], "name": row[1], "salary": row[3]}
        for row in selected
    ]


def test_randomized_database_and_arguments():
    """Exercise unknown argument combinations against a newly generated hierarchy."""
    rng = secrets.SystemRandom()
    ids = list(range(1001, 1049))
    rng.shuffle(ids)
    salary_pool = [52000, 61000, 73000, 88000, 95000, 95000, 112000, 135000, 160000]

    rows = []
    for index, employee_id in enumerate(ids):
        manager_id = None if index == 0 else rows[rng.randrange(index)][0]
        name = f"Employee {secrets.token_hex(4)} O'Neil \"{index}\""
        salary = rng.choice(salary_pool)
        department = f"Dept-{rng.randrange(6)}"
        rows.append((employee_id, name, manager_id, salary, department))

    cases = {
        (ids[0], 0, 100),
        (ids[0], max(salary_pool) + 1, 10),
        (max(ids) + 10000, 0, 10),
    }
    for _ in range(15):
        cases.add((
            rng.choice(ids),
            rng.randrange(50000, 165001),
            rng.randrange(1, 21),
        ))

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "company.db")
        shutil.copy2(DB_PATH, backup)
        new_fd, new_path = tempfile.mkstemp(prefix="company-test-", suffix=".db", dir="/home/user")
        os.close(new_fd)
        os.unlink(new_path)

        try:
            conn = sqlite3.connect(new_path)
            conn.execute(
                "CREATE TABLE employees ("
                "id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, "
                "salary INTEGER, department TEXT)"
            )
            conn.executemany("INSERT INTO employees VALUES (?, ?, ?, ?, ?)", rows)
            conn.commit()
            conn.close()
            os.chmod(new_path, 0o666)
            os.replace(new_path, DB_PATH)

            for manager_id, min_salary, limit in cases:
                actual = run_script_and_parse_json(manager_id, min_salary, limit)
                expected = expected_result(rows, manager_id, min_salary, limit)
                assert isinstance(actual, list), f"Expected a JSON array, got {type(actual).__name__}"
                for item in actual:
                    assert isinstance(item, dict), f"Each result must be an object, got {item!r}"
                    assert set(item.keys()) == {"id", "name", "salary"}, (
                        f"Object has incorrect keys: {item!r}"
                    )
                assert actual == expected, (
                    f"For arguments {(manager_id, min_salary, limit)}, "
                    f"expected {expected}, but got {actual}"
                )
        finally:
            for suffix in ("", "-wal", "-shm"):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)
            shutil.copy2(backup, DB_PATH)
            if os.path.exists(new_path):
                os.remove(new_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
