#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import csv
import json
import subprocess
import pytest

SCRIPT_PATH = "/home/user/find_anomalies.sh"
OUTPUT_JSON = "/home/user/anomalies.json"
DATA_DIR = "/home/user/data"


def compute_expected():
    employees = {}
    with open(os.path.join(DATA_DIR, "employees.csv"), "r") as f:
        for row in csv.DictReader(f):
            emp_id = row["emp_id"]
            version = int(row["version"])
            if emp_id not in employees or version > employees[emp_id]["version"]:
                employees[emp_id] = {
                    "name": row["name"],
                    "dept_id": row["dept_id"],
                    "version": version,
                }

    projects = {}
    with open(os.path.join(DATA_DIR, "projects.csv"), "r") as f:
        for row in csv.DictReader(f):
            proj_id = row["proj_id"]
            version = int(row["version"])
            if proj_id not in projects or version > projects[proj_id]["version"]:
                projects[proj_id] = {
                    "proj_name": row["proj_name"],
                    "dept_id": row["dept_id"],
                    "version": version,
                }

    works_on = {}
    with open(os.path.join(DATA_DIR, "works_on.csv"), "r") as f:
        for row in csv.DictReader(f):
            emp_id = row["emp_id"]
            version = int(row["version"])
            if emp_id not in works_on or version > works_on[emp_id]["version"]:
                works_on[emp_id] = {
                    "proj_id": row["proj_id"],
                    "version": version,
                }

    expected = []
    for emp_id, work in works_on.items():
        emp = employees.get(emp_id)
        proj = projects.get(work["proj_id"])
        if emp and proj and emp["dept_id"] != proj["dept_id"]:
            expected.append({
                "emp_name": emp["name"],
                "proj_name": proj["proj_name"],
            })
    expected.sort(key=lambda x: x["emp_name"])
    return expected


def read_and_validate_output(expected):
    assert os.path.isfile(OUTPUT_JSON), f"Output file {OUTPUT_JSON} does not exist. Did you run the script?"
    with open(OUTPUT_JSON, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON} is not a valid JSON file.")

    assert isinstance(actual, list), f"Expected {OUTPUT_JSON} to contain a JSON array."
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} anomalies, but found {len(actual)}."
    )
    for i, (item, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(item, dict), f"Object at index {i} is not a JSON object."
        assert "emp_name" in item, f"Object at index {i} is missing 'emp_name' key."
        assert "proj_name" in item, f"Object at index {i} is missing 'proj_name' key."
        assert set(item.keys()) == {"emp_name", "proj_name"}, (
            f"Object at index {i} must contain exactly 'emp_name' and 'proj_name'."
        )
        assert item["emp_name"] == wanted["emp_name"], (
            f"Mismatch at index {i}: Expected emp_name '{wanted['emp_name']}', got '{item['emp_name']}'"
        )
        assert item["proj_name"] == wanted["proj_name"], (
            f"Mismatch at index {i}: Expected proj_name '{wanted['proj_name']}', got '{item['proj_name']}'"
        )


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. stderr: {result.stderr}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the user."


def test_script_generates_anomalies_json():
    if os.path.exists(OUTPUT_JSON):
        os.remove(OUTPUT_JSON)
    run_script()
    assert os.path.isfile(OUTPUT_JSON), f"Script did not generate {OUTPUT_JSON}."


def test_anomalies_json_correct():
    expected_anomalies = compute_expected()
    read_and_validate_output(expected_anomalies)


def test_script_processes_changed_csv_data():
    paths = {
        name: os.path.join(DATA_DIR, name)
        for name in ("employees.csv", "projects.csv", "works_on.csv")
    }
    originals = {}
    for name, path in paths.items():
        with open(path, "rb") as f:
            originals[name] = f.read()

    challenge = {
        "employees.csv": """emp_id,name,dept_id,version
10,Zara,1,1
10,Zara,2,3
11,Aaron,5,1
12,Mona,9,2
""",
        "projects.csv": """proj_id,proj_name,dept_id,version
201,Old Name,1,1
201,Project Nova,7,2
202,Project Atlas,5,1
203,Project Zenith,8,1
""",
        "works_on.csv": """emp_id,proj_id,version
10,201,1
10,202,2
11,203,1
12,201,1
""",
    }

    try:
        for name, content in challenge.items():
            with open(paths[name], "w") as f:
                f.write(content)
        if os.path.exists(OUTPUT_JSON):
            os.remove(OUTPUT_JSON)
        run_script()
        read_and_validate_output(compute_expected())
    finally:
        for name, content in originals.items():
            with open(paths[name], "wb") as f:
                f.write(content)
        if os.path.isfile(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            subprocess.run(
                [SCRIPT_PATH], cwd="/home/user",
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
