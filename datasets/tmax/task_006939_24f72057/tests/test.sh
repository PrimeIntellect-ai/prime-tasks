#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE_PATH = "/home/user/export_hierarchy.c"
EXECUTABLE_PATH = "/home/user/export_hierarchy"
DB_PATH = "/home/user/company.db"
JSON_PATH = "/home/user/salary_rollup.json"

EXPECTED_ORIGINAL = [
    {"id": 1, "name": "Alice", "total_salary": 515000.00},
    {"id": 2, "name": "Bob", "total_salary": 205000.00},
    {"id": 3, "name": "Charlie", "total_salary": 210000.00},
    {"id": 4, "name": "Dave", "total_salary": 60000.00},
    {"id": 5, "name": "Eve", "total_salary": 65000.00},
    {"id": 6, "name": "Frank", "total_salary": 120000.00},
    {"id": 7, "name": "Grace", "total_salary": 50000.00},
]


def run_checked(command, timeout=20):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f"Duplicate JSON key: {key}"
        result[key] = value
    return result


def validate_output(expected):
    # Preserve the original existence and regular-file assertions.
    assert os.path.exists(JSON_PATH), f"Output file missing at {JSON_PATH}"
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file"

    with open(JSON_PATH, "r", encoding="utf-8") as output_file:
        raw = output_file.read()

    try:
        data = json.loads(raw, object_pairs_hook=reject_duplicate_keys)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise AssertionError(f"Failed to parse {JSON_PATH} as JSON: {exc}")

    assert isinstance(data, list), "JSON root must be a list (array)."
    assert len(data) == len(expected), (
        f"Expected {len(expected)} employee records, found {len(data)}."
    )

    # Every emitted total_salary must be a JSON number with exactly two digits
    # after the decimal point (not a quoted value or scientific notation).
    salary_tokens = re.findall(
        r'"total_salary"\s*:\s*(-?(?:0|[1-9][0-9]*)\.[0-9]{2})(?=\s*[,}])',
        raw,
    )
    assert len(salary_tokens) == len(expected), (
        "Every total_salary must be an unquoted JSON number formatted to exactly "
        "two decimal places."
    )

    for index, wanted in enumerate(expected):
        actual = data[index]
        assert isinstance(actual, dict), f"Item at index {index} is not a JSON object."
        assert set(actual.keys()) == {"id", "name", "total_salary"}, (
            f"Item at index {index} must have exactly the keys id, name, and total_salary."
        )
        assert type(actual["id"]) is int, f"id at index {index} must be an integer."
        assert isinstance(actual["name"], str), f"name at index {index} must be a string."
        assert type(actual["total_salary"]) in (int, float), (
            f"total_salary at index {index} must be a JSON number."
        )
        assert actual["id"] == wanted["id"], (
            f"Expected id {wanted['id']} at index {index}, got {actual['id']}."
        )
        assert actual["name"] == wanted["name"], (
            f"Expected name {wanted['name']} at index {index}, got {actual['name']}."
        )
        assert abs(float(actual["total_salary"]) - wanted["total_salary"]) < 0.01, (
            f"Expected total_salary {wanted['total_salary']} for id {wanted['id']}, "
            f"got {actual['total_salary']}."
        )


def make_random_database():
    rng = random.SystemRandom()
    ids = sorted(rng.sample(range(100, 1000), 9))
    records = []
    for index, employee_id in enumerate(ids):
        if index == 0:
            manager_id = None
        else:
            # Choosing only an earlier employee guarantees an acyclic hierarchy.
            manager_id = ids[rng.randrange(index)]
        name = f"Employee_{rng.randrange(10**8, 10**9)}"
        salary_cents = rng.randrange(3_000_000, 15_000_001)
        records.append((employee_id, name, manager_id, salary_cents))

    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    connection = sqlite3.connect(DB_PATH)
    try:
        connection.execute(
            "CREATE TABLE employees "
            "(id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, salary REAL)"
        )
        connection.executemany(
            "INSERT INTO employees (id, name, manager_id, salary) VALUES (?, ?, ?, ?)",
            [(employee_id, name, manager_id, cents / 100.0)
             for employee_id, name, manager_id, cents in records],
        )
        connection.commit()
    finally:
        connection.close()

    children = {employee_id: [] for employee_id, _, _, _ in records}
    salary_by_id = {}
    name_by_id = {}
    for employee_id, name, manager_id, cents in records:
        salary_by_id[employee_id] = cents
        name_by_id[employee_id] = name
        if manager_id is not None:
            children[manager_id].append(employee_id)

    def total_cents(employee_id):
        return salary_by_id[employee_id] + sum(
            total_cents(child_id) for child_id in children[employee_id]
        )

    return [
        {
            "id": employee_id,
            "name": name_by_id[employee_id],
            "total_salary": total_cents(employee_id) / 100.0,
        }
        for employee_id in ids
    ]


def main():
    assert os.path.exists(SOURCE_PATH), f"Missing required source file {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must not be a symbolic link"

    with open(SOURCE_PATH, "r", encoding="utf-8") as source_file:
        source = source_file.read()

    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "The C source must contain a WITH RECURSIVE SQL query."
    )
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), (
        "The program must open the SQLite database using SQLite's C API."
    )
    assert re.search(r"\bsqlite3_(?:prepare(?:_v2|_v3)?|exec|get_table)\s*\(", source), (
        "The program must execute its SQL through SQLite's C API."
    )

    backup_dir = tempfile.mkdtemp(prefix="hierarchy-verifier-")
    db_backup = os.path.join(backup_dir, "company.db")
    shutil.copy2(DB_PATH, db_backup)
    original_generated_output = None

    try:
        # Compile exactly the requested artifact from the submitted source.
        run_checked([
            "gcc", "-o", EXECUTABLE_PATH, SOURCE_PATH, "-lsqlite3"
        ])
        assert os.path.isfile(EXECUTABLE_PATH), (
            f"Compiled executable missing at {EXECUTABLE_PATH}"
        )
        assert os.access(EXECUTABLE_PATH, os.X_OK), (
            f"{EXECUTABLE_PATH} is not executable"
        )

        # Execute against the task's original database and retain all original
        # expected-content assertions.
        if os.path.exists(JSON_PATH):
            os.unlink(JSON_PATH)
        run_checked([EXECUTABLE_PATH])
        validate_output(EXPECTED_ORIGINAL)
        with open(JSON_PATH, "rb") as output_file:
            original_generated_output = output_file.read()

        # Replace the database with an unpredictable hierarchy, rerun the
        # submitted executable, and derive expected rollups independently.
        expected_random = make_random_database()
        if os.path.exists(JSON_PATH):
            os.unlink(JSON_PATH)
        run_checked([EXECUTABLE_PATH])
        validate_output(expected_random)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.unlink(path)
        shutil.copy2(db_backup, DB_PATH)
        if original_generated_output is not None:
            with open(JSON_PATH, "wb") as output_file:
                output_file.write(original_generated_output)
        shutil.rmtree(backup_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
