#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/generate_audit.sh"
DB_PATH = "/home/user/compliance.db"
HEADER = "EmployeeName,SystemName,AccessDate,EmployeeClearance,RequiredClearance"


def run_script(*args):
    return subprocess.run([SCRIPT_PATH, *map(str, args)], capture_output=True, text=True, timeout=10)


def normalize_output(value):
    return value.strip().replace('\r\n', '\n')


def expected_output(conn, employee_id):
    rows = conn.execute(
        """
        WITH RECURSIVE management_chain(emp_id) AS (
            SELECT emp_id FROM personnel WHERE emp_id = ?
            UNION ALL
            SELECT p.emp_id
            FROM personnel AS p
            JOIN management_chain AS m ON p.manager_id = m.emp_id
        )
        SELECT p.full_name, s.sys_name, a.access_date,
               p.clearance_level, s.required_clearance
        FROM management_chain AS m
        JOIN personnel AS p ON p.emp_id = m.emp_id
        JOIN access_events AS a ON a.emp_id = p.emp_id
        JOIN it_systems AS s ON s.system_id = a.system_id
        WHERE s.required_clearance > p.clearance_level
        ORDER BY a.access_date ASC, p.full_name ASC
        """,
        (employee_id,),
    ).fetchall()
    lines = [HEADER]
    lines.extend(",".join(str(value) for value in row) for row in rows)
    return "\n".join(lines)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_uses_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as script_file:
        source = script_file.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "Script must use a recursive SQL CTE"
    )


def test_script_output_id_2():
    expected_output = (
        "EmployeeName,SystemName,AccessDate,EmployeeClearance,RequiredClearance\n"
        "Charlie Lead,FinanceDB,2023-10-03,3,4\n"
        "Eve Intern,DevServer,2023-10-05,1,2\n"
        "Frank Rogue,CoreInfra,2023-10-06,2,5\n"
        "Dave Worker,CoreInfra,2023-10-07,2,5"
    )

    result = run_script("2")
    assert result.returncode == 0, f"Script exited with non-zero code for ID 2: {result.stderr}"

    actual_output = normalize_output(result.stdout)
    assert actual_output == expected_output, (
        f"Output for ID 2 did not match expected.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_output}"
    )


def test_script_output_id_3():
    expected_output = (
        "EmployeeName,SystemName,AccessDate,EmployeeClearance,RequiredClearance\n"
        "Charlie Lead,FinanceDB,2023-10-03,3,4\n"
        "Eve Intern,DevServer,2023-10-05,1,2\n"
        "Dave Worker,CoreInfra,2023-10-07,2,5"
    )

    result = run_script("3")
    assert result.returncode == 0, f"Script exited with non-zero code for ID 3: {result.stderr}"

    actual_output = normalize_output(result.stdout)
    assert actual_output == expected_output, (
        f"Output for ID 3 did not match expected.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_output}"
    )


def test_requires_exactly_one_argument():
    no_args = run_script()
    assert no_args.returncode != 0, "Script must reject calls with no Employee ID"

    too_many = run_script("2", "3")
    assert too_many.returncode != 0, "Script must reject calls with more than one argument"


def test_dynamic_database_contents_and_parameter_safety():
    original_db = open(DB_PATH, "rb").read()
    suffix = secrets.token_hex(5)
    base = 100000 + secrets.randbelow(800000)
    root, child, grandchild, great_grandchild, sibling = range(base, base + 5)
    system_base = base + 100
    low_system, medium_system, high_system = range(system_base, system_base + 3)
    event_base = base + 500

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.executemany(
            "INSERT INTO personnel(emp_id, full_name, manager_id, clearance_level) VALUES (?, ?, ?, ?)",
            [
                (root, f"Audit Root {suffix}", None, 1),
                (child, f"Audit Child {suffix}", root, 4),
                (grandchild, f"Audit Grandchild {suffix}", child, 2),
                (great_grandchild, f"Audit GreatGrandchild {suffix}", grandchild, 1),
                (sibling, f"Audit Sibling {suffix}", root, 3),
            ],
        )
        conn.executemany(
            "INSERT INTO it_systems(system_id, sys_name, required_clearance) VALUES (?, ?, ?)",
            [
                (low_system, f"LowSystem{suffix}", 1),
                (medium_system, f"MediumSystem{suffix}", 3),
                (high_system, f"HighSystem{suffix}", 5),
            ],
        )
        conn.executemany(
            "INSERT INTO access_events(event_id, emp_id, system_id, access_date) VALUES (?, ?, ?, ?)",
            [
                (event_base, root, high_system, "2037-04-01 08:00:00"),
                (event_base + 1, child, high_system, "2037-04-02 08:00:00"),
                (event_base + 2, grandchild, medium_system, "2037-04-03 08:00:00"),
                (event_base + 3, great_grandchild, high_system, "2037-04-04 08:00:00"),
                (event_base + 4, sibling, high_system, "2037-04-03 08:00:00"),
                (event_base + 5, sibling, low_system, "2037-04-05 08:00:00"),
            ],
        )
        conn.commit()

        for employee_id in (1, 4, 5, 6, root, child, grandchild, base + 9999):
            expected = expected_output(conn, employee_id)
            result = run_script(str(employee_id))
            assert result.returncode == 0, (
                f"Script failed for Employee ID {employee_id}: {result.stderr}"
            )
            assert normalize_output(result.stdout) == expected, (
                f"Incorrect output for Employee ID {employee_id}.\n"
                f"Expected:\n{expected}\n\nActual:\n{normalize_output(result.stdout)}"
            )

        injection = f"{root} OR 1=1"
        result = run_script(injection)
        assert result.returncode == 0, f"Script failed on safely supplied non-ID input: {result.stderr}"
        assert normalize_output(result.stdout) == HEADER, (
            "Employee ID appears to have been interpreted as SQL rather than as one parameter"
        )
        assert conn.execute(
            "SELECT COUNT(*) FROM personnel WHERE emp_id = ?", (root,)
        ).fetchone()[0] == 1
        conn.close()
    finally:
        try:
            conn.close()
        except Exception:
            pass
        for suffix_path in ("-journal", "-wal", "-shm"):
            try:
                os.remove(DB_PATH + suffix_path)
            except FileNotFoundError:
                pass
        with open(DB_PATH, "wb") as db_file:
            db_file.write(original_db)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
