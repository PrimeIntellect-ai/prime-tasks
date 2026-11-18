#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_REAL="$(mktemp /tmp/sqlite3.real.XXXXXX)"
SQLITE_LOG="/tmp/verifier_sqlite.log"
cp -a /usr/bin/sqlite3 "$SQLITE_REAL"
: > "$SQLITE_LOG"

restore_sqlite() {
    cp -a "$SQLITE_REAL" /usr/bin/sqlite3
    rm -f "$SQLITE_REAL"
}
trap restore_sqlite EXIT

cat > /usr/bin/sqlite3 <<WRAPPER_EOF
#!/bin/bash
input_file="\$(mktemp /tmp/sqlite-input.XXXXXX)"
cat > "\$input_file"
{
    echo '=== invocation ==='
    printf '%s\n' "\$@"
    cat "\$input_file"
} >> "$SQLITE_LOG"
"$SQLITE_REAL" "\$@" < "\$input_file"
status=\$?
rm -f "\$input_file"
exit \$status
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import stat
import string
import subprocess

import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
RESULTS_PATH = "/home/user/results.csv"
EMPLOYEES_PATH = "/home/user/employees.csv"
SQLITE_LOG = "/tmp/verifier_sqlite.log"
HEADER = [
    "emp_id", "name", "department", "salary", "management_level",
    "dept_avg_salary", "salary_rank_in_dept"
]


def test_analyze_script_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_analyze_script_execution_and_output():
    script_path = "/home/user/analyze.sh"
    results_path = "/home/user/results.csv"

    # Remove results.csv if it exists to ensure we are testing the script's output
    if os.path.exists(results_path):
        os.remove(results_path)

    # Execute the script
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.exists(results_path), f"Output file {results_path} was not created."

    expected_rows = [
        ["emp_id", "name", "department", "salary", "management_level", "dept_avg_salary", "salary_rank_in_dept"],
        ["2", "Bob", "Engineering", "150000", "1", "115000", "1"],
        ["4", "David", "Engineering", "120000", "2", "115000", "2"],
        ["5", "Eve", "Engineering", "110000", "2", "115000", "3"],
        ["8", "Heidi", "Engineering", "80000", "3", "115000", "4"],
        ["1", "Alice", "Executive", "200000", "0", "200000", "1"],
        ["3", "Charlie", "Sales", "140000", "1", "110000", "1"],
        ["7", "Grace", "Sales", "100000", "2", "110000", "2"],
        ["6", "Frank", "Sales", "90000", "2", "110000", "3"]
    ]

    with open(results_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, "The output in results.csv does not match the expected data and ordering."


def assert_required_sql_was_executed(sql_text):
    assert "=== invocation ===" in sql_text, "analyze.sh did not execute sqlite3."
    assert re.search(r"\bWITH\s+RECURSIVE\b", sql_text, re.IGNORECASE), \
        "The SQL executed by analyze.sh did not use a recursive CTE."
    assert re.search(r"\bAVG\s*\([^)]*\)\s*OVER\s*\(", sql_text, re.IGNORECASE | re.DOTALL), \
        "The SQL executed by analyze.sh did not calculate the department average with a window function."
    assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", sql_text, re.IGNORECASE | re.DOTALL), \
        "The SQL executed by analyze.sh did not calculate salary rank with RANK()."


def test_required_sqlite_features_were_exercised():
    with open(SQLITE_LOG, "r", encoding="utf-8", errors="replace") as f:
        assert_required_sql_was_executed(f.read())


def make_dataset(rng, count):
    token = "".join(rng.choice(string.ascii_uppercase) for _ in range(7))
    departments = [f"Dept_A_{token}", f"Dept_M_{token}", f"Dept_Z_{token}"]
    ids = rng.sample(range(1000, 9000), count)
    rows = []
    used_salaries = {d: set() for d in departments}

    for i in range(count):
        department = rng.choice(departments)
        salary = rng.randrange(47000, 230000)
        while salary in used_salaries[department]:
            salary = rng.randrange(47000, 230000)
        used_salaries[department].add(salary)
        manager = "" if i == 0 else str(ids[rng.randrange(0, i)])
        rows.append([
            str(ids[i]), f"Person_{token}_{i}", manager, str(salary), department
        ])

    rng.shuffle(rows)
    return rows


def expected_for(rows):
    by_id = {row[0]: row for row in rows}
    levels = {}

    def level(emp_id):
        if emp_id in levels:
            return levels[emp_id]
        manager_id = by_id[emp_id][2]
        levels[emp_id] = 0 if manager_id == "" else level(manager_id) + 1
        return levels[emp_id]

    dept_salaries = {}
    for row in rows:
        dept_salaries.setdefault(row[4], []).append(int(row[3]))

    output = []
    for row in rows:
        emp_id, name, _manager, salary_text, department = row
        salary = int(salary_text)
        salaries = dept_salaries[department]
        average = math.floor(sum(salaries) / len(salaries) + 0.5)
        rank = 1 + sum(other > salary for other in salaries)
        output.append([
            emp_id, name, department, salary_text, str(level(emp_id)),
            str(average), str(rank)
        ])

    output.sort(key=lambda row: (row[2], int(row[6])))
    return [HEADER] + output


def run_and_read_with_sql_check():
    before = os.path.getsize(SQLITE_LOG)
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Script failed on a changed input. stderr: {result.stderr}"
    assert os.path.isfile(RESULTS_PATH), "analyze.sh did not create results.csv on a changed input."

    with open(SQLITE_LOG, "r", encoding="utf-8", errors="replace") as f:
        f.seek(before)
        assert_required_sql_was_executed(f.read())

    with open(RESULTS_PATH, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def test_computes_results_for_unseen_inputs():
    with open(EMPLOYEES_PATH, "rb") as f:
        original = f.read()

    rng = random.SystemRandom()
    try:
        for count in (11, 14):
            rows = make_dataset(rng, count)
            with open(EMPLOYEES_PATH, "w", encoding="utf-8", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["emp_id", "name", "manager_id", "salary", "department"])
                writer.writerows(rows)

            actual = run_and_read_with_sql_check()
            assert actual == expected_for(rows), \
                "results.csv was not correctly recomputed from an unseen employees.csv hierarchy."
    finally:
        with open(EMPLOYEES_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
