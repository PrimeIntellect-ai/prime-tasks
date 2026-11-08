#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import secrets
import sqlite3
import subprocess
import pytest

SCRIPT = '/home/user/query_pipeline.py'
DB = pathlib.Path('/home/user/company.db')
DEPARTMENTS = pathlib.Path('/home/user/departments.jsonl')
OUTPUT = pathlib.Path('/home/user/optimized_reports.json')


def test_optimized_reports_exists():
    file_path = '/home/user/optimized_reports.json'
    assert os.path.exists(file_path), f"Expected output file '{file_path}' does not exist."


def test_optimized_reports_content():
    file_path = '/home/user/optimized_reports.json'
    assert os.path.exists(file_path), f"Expected output file '{file_path}' does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File '{file_path}' does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of objects."

    expected_data = [
        {
            "department": "Executive",
            "manager": "Alice (CEO)",
            "reports": [
                "Bob (VP Eng)",
                "Charlie (VP Sales)",
                "Grace (HR)"
            ]
        },
        {
            "department": "Engineering",
            "manager": "Bob (VP Eng)",
            "reports": [
                "David (Eng)",
                "Eve (Eng)"
            ]
        },
        {
            "department": "Engineering",
            "manager": "David (Eng)",
            "reports": [
                "Ivan (Eng Intern)"
            ]
        },
        {
            "department": "Human Resources",
            "manager": "Grace (HR)",
            "reports": [
                "Heidi (HR Intern)"
            ]
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} managers in the output, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert "manager" in actual, f"Object at index {i} is missing the 'manager' key."
        assert "department" in actual, f"Object at index {i} is missing the 'department' key."
        assert "reports" in actual, f"Object at index {i} is missing the 'reports' key."

        assert actual["manager"] == expected["manager"], f"Expected manager '{expected['manager']}' at index {i}, got '{actual.get('manager')}'."
        assert actual["department"] == expected["department"], f"Expected department '{expected['department']}' for manager '{expected['manager']}', got '{actual.get('department')}'."

        actual_reports = actual["reports"]
        expected_reports = expected["reports"]
        assert isinstance(actual_reports, list), f"'reports' for manager '{expected['manager']}' must be a list."
        assert actual_reports == expected_reports, f"Reports for manager '{expected['manager']}' do not match expected or are not sorted correctly. Expected: {expected_reports}, Got: {actual_reports}"


def test_pipeline_reads_and_joins_both_sources():
    token = secrets.token_hex(8)

    def unique_ids(count):
        values = set()
        while len(values) < count:
            values.add(1000 + secrets.randbelow(900000))
        return list(values)

    employee_ids = unique_ids(8)
    dept_ids = unique_ids(4)
    m_zeta, m_alpha, m_gamma, r_zebra, r_alpha, r_boundary, r_gamma, lone = employee_ids
    d_high_one, d_boundary, d_high_two, d_decoy = dept_ids

    employees = [
        (m_zeta, f'Manager Zeta {token}', None, d_high_one),
        (m_alpha, f'Manager Alpha {token}', None, d_boundary),
        (m_gamma, f'Manager Gamma {token}', None, d_high_two),
        (r_zebra, f'Report Zebra {token}', m_zeta, d_decoy),
        (r_alpha, f'Report Alpha {token}', m_zeta, d_boundary),
        (r_boundary, f'Boundary Report {token}', m_alpha, d_high_one),
        (r_gamma, f'Gamma Report {token}', m_gamma, d_boundary),
        (lone, f'No Reports {token}', None, d_high_one),
    ]
    departments = [
        {"dept_id": d_high_one, "dept_name": f'High One {token}', "budget": 500001 + secrets.randbelow(100000)},
        {"dept_id": d_boundary, "dept_name": f'Boundary {token}', "budget": 500000},
        {"dept_id": d_high_two, "dept_name": f'High Two {token}', "budget": 700000 + secrets.randbelow(100000)},
        {"dept_id": d_decoy, "dept_name": f'Decoy {token}', "budget": secrets.randbelow(500000)},
    ]

    by_id = {row[0]: row for row in employees}
    departments_by_id = {row['dept_id']: row for row in departments}
    reports_by_manager = {}
    for employee in employees:
        if employee[2] is not None:
            reports_by_manager.setdefault(employee[2], []).append(employee[1])

    expected = []
    for manager_id, report_names in reports_by_manager.items():
        manager = by_id[manager_id]
        department = departments_by_id[manager[3]]
        if department['budget'] > 500000:
            expected.append({
                'manager': manager[1],
                'department': department['dept_name'],
                'reports': sorted(report_names),
            })
    expected.sort(key=lambda row: row['manager'])

    backups = {
        DB: DB.read_bytes(),
        DEPARTMENTS: DEPARTMENTS.read_bytes(),
        OUTPUT: OUTPUT.read_bytes(),
    }

    sidecars = [pathlib.Path(str(DB) + suffix) for suffix in ('-wal', '-shm', '-journal')]
    try:
        for sidecar in sidecars:
            sidecar.unlink(missing_ok=True)
        DB.unlink(missing_ok=True)

        shuffled_employees = employees[:]
        random.SystemRandom().shuffle(shuffled_employees)
        conn = sqlite3.connect(DB)
        try:
            conn.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER)')
            conn.executemany('INSERT INTO employees VALUES (?,?,?,?)', shuffled_employees)
            conn.commit()
        finally:
            conn.close()

        shuffled_departments = departments[:]
        random.SystemRandom().shuffle(shuffled_departments)
        with DEPARTMENTS.open('w') as f:
            for department in shuffled_departments:
                f.write(json.dumps(department) + '\n')

        OUTPUT.unlink(missing_ok=True)
        subprocess.run(['python3', SCRIPT], cwd='/home/user', check=True, timeout=20)
        assert OUTPUT.is_file(), "The pipeline did not create /home/user/optimized_reports.json."

        try:
            actual = json.loads(OUTPUT.read_text())
        except json.JSONDecodeError:
            pytest.fail("The pipeline output for the exercised inputs is not valid JSON.")

        assert isinstance(actual, list), "The exercised pipeline output must be a list."
        assert len(actual) == len(expected), f"Expected {len(expected)} managers for exercised inputs, found {len(actual)}."
        for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
            assert "manager" in actual_row, f"Object at index {i} is missing the 'manager' key."
            assert "department" in actual_row, f"Object at index {i} is missing the 'department' key."
            assert "reports" in actual_row, f"Object at index {i} is missing the 'reports' key."
            assert actual_row['manager'] == expected_row['manager']
            assert actual_row['department'] == expected_row['department']
            assert isinstance(actual_row['reports'], list)
            assert actual_row['reports'] == expected_row['reports']
    finally:
        for sidecar in sidecars:
            sidecar.unlink(missing_ok=True)
        for path, contents in backups.items():
            path.write_bytes(contents)
TEST_EOF

if [ -f /home/user/query_pipeline.py ] \
   && rm -f /home/user/optimized_reports.json \
   && timeout 20s python3 /home/user/query_pipeline.py \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
