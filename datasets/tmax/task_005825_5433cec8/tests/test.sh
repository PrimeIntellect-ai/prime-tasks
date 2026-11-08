#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import string
import subprocess


def test_c_source_file_exists():
    assert os.path.exists('/home/user/process.c'), "/home/user/process.c does not exist."
    assert os.path.isfile('/home/user/process.c'), "/home/user/process.c is not a file."


def test_c_executable_exists():
    assert os.path.exists('/home/user/process'), "/home/user/process executable does not exist."
    assert os.path.isfile('/home/user/process'), "/home/user/process is not a file."
    assert os.access('/home/user/process', os.X_OK), "/home/user/process is not executable."


def test_output_csv_exists():
    assert os.path.exists('/home/user/output.csv'), "/home/user/output.csv does not exist."
    assert os.path.isfile('/home/user/output.csv'), "/home/user/output.csv is not a file."


def test_output_csv_content_and_encoding():
    try:
        with open('/home/user/output.csv', 'r', encoding='utf-8', newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
    except UnicodeDecodeError:
        assert False, "/home/user/output.csv is not valid UTF-8."
    except Exception as e:
        assert False, f"Failed to read /home/user/output.csv: {e}"

    expected_rows = [
        ["ID", "Department", "Feedback"],
        ["1", "Sales", "Great work"],
        ["2", "Engineering", "Needs\nimprovement"],
        ["3", "Sales", "Café is nice"],
        ["5", "Engineering", "Good"]
    ]

    assert rows == expected_rows, f"The content of /home/user/output.csv is incorrect. Expected {expected_rows}, but got {rows}."


def test_source_compiles_to_required_executable():
    result = subprocess.run(
        ['gcc', '-o', '/home/user/process', '/home/user/process.c'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"process.c failed to compile with gcc: {result.stderr}"
    assert os.path.isfile('/home/user/process')
    assert os.access('/home/user/process', os.X_OK)


def _write_input(rows):
    with open('/home/user/input.csv', 'w', encoding='iso-8859-1', newline='') as f:
        csv.writer(f, lineterminator='\r\n').writerows(rows)


def _expected_sample(rows):
    result = [rows[0]]
    counts = {}
    for row in rows[1:]:
        department = row[1]
        count = counts.get(department, 0)
        if count < 2:
            result.append(row)
        counts[department] = count + 1
    return result


def _run_and_read(expected):
    try:
        os.remove('/home/user/output.csv')
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ['/home/user/process'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"process exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    assert os.path.exists('/home/user/output.csv'), "process did not create /home/user/output.csv"
    assert os.path.isfile('/home/user/output.csv'), "/home/user/output.csv is not a file"

    raw = open('/home/user/output.csv', 'rb').read()
    try:
        raw.decode('utf-8')
    except UnicodeDecodeError as e:
        assert False, f"generated output is not valid UTF-8: {e}"

    try:
        with open('/home/user/output.csv', 'r', encoding='utf-8', newline='') as f:
            actual = list(csv.reader(f))
    except Exception as e:
        assert False, f"generated output is not valid CSV: {e}"

    assert actual == expected, f"runtime output was incorrect. Expected {expected}, got {actual}"


def test_executable_processes_fresh_csv_input():
    rng = secrets.SystemRandom()
    token = ''.join(rng.choice(string.ascii_letters) for _ in range(10))
    departments = [
        f'Ventes-{token}',
        f'R&D, équipe-{token}',
        f'Bureau "Café"-{token}',
        f'Support-{token}',
    ]

    order = [department for department in departments for _ in range(4)]
    rng.shuffle(order)
    start_id = rng.randrange(10000, 90000)
    rows = [['ID', 'Department', 'Feedback']]
    for i, department in enumerate(order):
        feedback = f'Café numéro {i}, dit "bonjour"\nSuite avec £ et piñata {token}'
        rows.append([str(start_id + i), department, feedback])

    expected = _expected_sample(rows)
    _write_input(rows)
    _run_and_read(expected)

    token2 = ''.join(rng.choice(string.ascii_letters) for _ in range(10))
    rows2 = [
        ['ID', 'Department', 'Feedback'],
        ['1', f'Alpha-{token2}', 'déjà vu'],
        ['2', f'Alpha-{token2}', 'première ligne\nseconde ligne'],
        ['3', f'Alpha-{token2}', 'must be omitted'],
        ['4', f'Bêta, "{token2}"', 'élève, très bien'],
        ['5', f'Bêta, "{token2}"', 'quote: "oui"\nand newline'],
        ['6', f'Bêta, "{token2}"', 'must also be omitted'],
    ]
    expected2 = _expected_sample(rows2)
    _write_input(rows2)
    _run_and_read(expected2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
