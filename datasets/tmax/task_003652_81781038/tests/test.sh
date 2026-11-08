#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

DB_PATH = "/home/user/company.db"
SOURCE_PATH = "/home/user/hierarchy.c"
BINARY_PATH = "/home/user/hierarchy"
OUTPUT_PATH = "/home/user/output.json"


@pytest.fixture(scope="session", autouse=True)
def restore_files_after_tests():
    temp_dir = tempfile.mkdtemp(prefix="hierarchy-verifier-")
    db_backup = os.path.join(temp_dir, "company.db")
    shutil.copy2(DB_PATH, db_backup)

    output_existed = os.path.isfile(OUTPUT_PATH)
    output_backup = os.path.join(temp_dir, "output.json")
    if output_existed:
        shutil.copy2(OUTPUT_PATH, output_backup)

    yield

    shutil.copy2(db_backup, DB_PATH)
    if output_existed:
        shutil.copy2(output_backup, OUTPUT_PATH)
    elif os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    shutil.rmtree(temp_dir, ignore_errors=True)


def run_program(manager_id, limit, offset):
    result = subprocess.run(
        [BINARY_PATH, str(manager_id), str(limit), str(offset)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program failed for arguments {manager_id} {limit} {offset}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} not found after execution."
    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON: {exc}")
    assert isinstance(data, list), "Program output must be a JSON array."
    return data


def independently_expected(manager_id, limit, offset):
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT id, name, manager_id FROM employees").fetchall()
    conn.close()

    employees = {row[0]: (row[1], row[2]) for row in rows}
    if manager_id not in employees:
        return []

    children = {}
    for employee_id, name, parent_id in rows:
        children.setdefault(parent_id, []).append(employee_id)

    result = []
    queue = [(manager_id, 0)]
    seen = set()
    while queue:
        employee_id, depth = queue.pop(0)
        if employee_id in seen:
            continue
        seen.add(employee_id)
        result.append({"id": employee_id, "name": employees[employee_id][0], "depth": depth})
        for child_id in children.get(employee_id, []):
            queue.append((child_id, depth + 1))

    result.sort(key=lambda item: (item["depth"], item["name"]))
    return result[offset:offset + limit]


def test_index_exists():
    db_path = "/home/user/company.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='employees';")
    indices = cursor.fetchall()
    conn.close()

    found = False
    for (sql,) in indices:
        if sql and "manager_id" in sql.lower():
            found = True
            break

    assert found, "No index found on the 'manager_id' column in the 'employees' table."


def test_index_really_indexes_manager_id():
    conn = sqlite3.connect(DB_PATH)
    index_names = [row[1] for row in conn.execute("PRAGMA index_list('employees')")]
    found = False
    for index_name in index_names:
        escaped = index_name.replace("'", "''")
        columns = [row[2] for row in conn.execute(f"PRAGMA index_info('{escaped}')")]
        if "manager_id" in columns:
            found = True
            break
    conn.close()
    assert found, "No employees index has manager_id as an indexed key column."


def test_c_source_exists():
    c_file = "/home/user/hierarchy.c"
    assert os.path.isfile(c_file), f"{c_file} not found."


def test_source_uses_required_sqlite_api_and_recursive_cte():
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    lowered = source_without_comments.lower()
    assert "sqlite3_prepare_v2" in lowered, "Source does not use sqlite3_prepare_v2."
    assert "sqlite3_bind_int" in lowered, "Source does not bind integer parameters."
    assert "sqlite3_step" in lowered, "Source does not use sqlite3_step."
    assert re.search(r"\bwith\s+recursive\b", lowered), "Source does not contain a recursive CTE."


def test_compile_and_execute_required_invocation():
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)
    run_program(1, 4, 2)


def test_output_json_validity_and_content():
    output_path = "/home/user/output.json"
    assert os.path.isfile(output_path), f"{output_path} not found."

    with open(output_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_data = [
        {"id": 3, "name": "Charlie", "depth": 1},
        {"id": 4, "name": "David", "depth": 2},
        {"id": 5, "name": "Eve", "depth": 2},
        {"id": 6, "name": "Frank", "depth": 2}
    ]

    assert actual_data == expected_data, (
        f"JSON output does not match the expected structure and content.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {actual_data}"
    )


def test_program_on_unseen_data_and_arguments():
    token = uuid.uuid4().hex[:10]
    conn = sqlite3.connect(DB_PATH)
    base = conn.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM employees").fetchone()[0]
    inserted = [
        (base, f"Root_{token}", None),
        (base + 1, f"Zulu_{token}", base),
        (base + 2, f"Alpha_{token}", base),
        (base + 3, f"Middle_{token}", base + 1),
        (base + 4, f"Beta_{token}", base + 2),
        (base + 5, f"Omega_{token}", base + 2),
    ]
    conn.executemany("INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)", inserted)
    conn.commit()
    conn.close()

    for manager_id, limit, offset in [
        (base, 3, 1),
        (base + 2, 10, 0),
        (base, 2, 4),
    ]:
        expected = independently_expected(manager_id, limit, offset)
        actual = run_program(manager_id, limit, offset)
        assert actual == expected, (
            f"Incorrect result for arguments {manager_id} {limit} {offset}.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
