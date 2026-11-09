#!/bin/bash
mkdir -p /logs/verifier

TMPDIR_VERIFY=$(mktemp -d)
cp /home/user/employees.csv "$TMPDIR_VERIFY/employees.csv"
cp /home/user/departments.csv "$TMPDIR_VERIFY/departments.csv"

cleanup() {
    cp "$TMPDIR_VERIFY/employees.csv" /home/user/employees.csv 2>/dev/null || true
    cp "$TMPDIR_VERIFY/departments.csv" /home/user/departments.csv 2>/dev/null || true
    if [ -f "$TMPDIR_VERIFY/dept_metrics.json" ]; then
        cp "$TMPDIR_VERIFY/dept_metrics.json" /home/user/dept_metrics.json 2>/dev/null || true
    fi
    rm -rf "$TMPDIR_VERIFY"
}
trap cleanup EXIT

verify() {
    python3 - <<'PY' || return 1
import os
import re

path = "/home/user/generate_summary.sh"
assert os.path.exists(path), f"File {path} is missing."
assert os.path.isfile(path), f"{path} should be a regular file."
with open(path, "r", encoding="utf-8") as f:
    source = f.read()
# Ignore full-line shell and SQL comments when checking for the requested CTE.
code = "\n".join(
    line for line in source.splitlines()
    if not line.lstrip().startswith(("#", "--"))
)
assert re.search(r"\bWITH\s+RECURSIVE\b", code, re.IGNORECASE), \
    "generate_summary.sh must include a recursive CTE using WITH RECURSIVE."
PY

    rm -f /home/user/dept_metrics.json
    timeout 20s bash /home/user/generate_summary.sh || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_dept_metrics_exists():
    path = "/home/user/dept_metrics.json"
    assert os.path.exists(path), f"File {path} is missing. The script must generate this file."
    assert os.path.isfile(path), f"{path} should be a file."

def test_dept_metrics_content():
    path = "/home/user/dept_metrics.json"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON in {path} must be an array of objects."
    assert len(data) == 3, f"Expected 3 departments in the output, found {len(data)}."

    expected_data = [
        {
            "department": "Engineering",
            "employee_count": 4,
            "avg_depth": 1.5
        },
        {
            "department": "HR",
            "employee_count": 1,
            "avg_depth": 1.0
        },
        {
            "department": "Sales",
            "employee_count": 2,
            "avg_depth": 1.5
        }
    ]

    # Check alphabetical order by department name
    departments = [item.get("department") for item in data]
    assert departments == ["Engineering", "HR", "Sales"], "The JSON output must be ordered alphabetically by department name."

    for i, expected in enumerate(expected_data):
        actual = data[i]
        assert actual.get("department") == expected["department"], f"Expected department {expected['department']}, got {actual.get('department')}."
        assert actual.get("employee_count") == expected["employee_count"], f"Incorrect employee_count for {expected['department']}."

        # Float comparison for avg_depth
        actual_depth = actual.get("avg_depth")
        assert actual_depth is not None, f"Missing avg_depth for {expected['department']}."
        assert isinstance(actual_depth, (int, float)), f"avg_depth for {expected['department']} must be a number."
        assert abs(float(actual_depth) - expected["avg_depth"]) < 0.01, f"Incorrect avg_depth for {expected['department']}. Expected {expected['avg_depth']}, got {actual_depth}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
    cp /home/user/dept_metrics.json "$TMPDIR_VERIFY/dept_metrics.json" || return 1

    cat <<'EOF' > /home/user/departments.csv
 dept_id,dept_name
10,Alpha
20,Beta
30,Gamma
40,Zeta
EOF
    # Remove the accidental leading space in the header while retaining a literal fixture.
    sed -i '1s/^ //' /home/user/departments.csv || return 1

    cat <<'EOF' > /home/user/employees.csv
emp_id,name,dept_id,manager_id
1,Root,20,
2,One,10,1
3,Two,10,2
4,Three,30,3
5,Four,20,1
6,Five,30,5
7,Six,40,6
8,Seven,40,7
EOF

    rm -f /home/user/dept_metrics.json
    timeout 20s bash /home/user/generate_summary.sh || return 1

    python3 - <<'PY' || return 1
import csv
import json
import os

output = "/home/user/dept_metrics.json"
assert os.path.exists(output), f"File {output} is missing after running the script on a second fixture."
assert os.path.isfile(output), f"{output} should be a file."

with open("/home/user/departments.csv", newline="", encoding="utf-8") as f:
    departments = {int(r["dept_id"]): r["dept_name"] for r in csv.DictReader(f)}
with open("/home/user/employees.csv", newline="", encoding="utf-8") as f:
    employees = list(csv.DictReader(f))

by_id = {int(r["emp_id"]): r for r in employees}
depths = {}
def depth(emp_id):
    if emp_id in depths:
        return depths[emp_id]
    manager = by_id[emp_id]["manager_id"].strip()
    value = 0 if manager == "" else depth(int(manager)) + 1
    depths[emp_id] = value
    return value

expected = []
for dept_id, name in departments.items():
    members = [r for r in employees if int(r["dept_id"]) == dept_id]
    member_depths = [depth(int(r["emp_id"])) for r in members]
    expected.append({
        "department": name,
        "employee_count": len(members),
        "avg_depth": sum(member_depths) / len(member_depths),
    })
expected.sort(key=lambda x: x["department"])

try:
    with open(output, encoding="utf-8") as f:
        actual = json.load(f)
except json.JSONDecodeError as e:
    raise AssertionError(f"File {output} does not contain valid JSON: {e}")

assert isinstance(actual, list), f"The JSON in {output} must be an array of objects."
assert len(actual) == len(expected), f"Expected {len(expected)} departments, found {len(actual)}."
assert [x.get("department") for x in actual] == [x["department"] for x in expected], \
    "The JSON output must include every department in alphabetical order."
for got, want in zip(actual, expected):
    assert got.get("department") == want["department"]
    assert got.get("employee_count") == want["employee_count"], \
        f"Incorrect employee_count for {want['department']}."
    value = got.get("avg_depth")
    assert isinstance(value, (int, float)) and not isinstance(value, bool), \
        f"avg_depth for {want['department']} must be a number."
    assert abs(float(value) - want["avg_depth"]) < 0.01, \
        f"Incorrect avg_depth for {want['department']}: expected {want['avg_depth']}, got {value}."
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
