#!/bin/bash
set -u
mkdir -p /logs/verifier
status=0

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import json
import os
import py_compile
import secrets
import stat
import subprocess

BASE_DIR = "/home/user/ticket_8821"
DATA_FILE = os.path.join(BASE_DIR, "data", "org.json")
OUTPUT_FILE = os.path.join(BASE_DIR, "output", "summary.json")
RUN_SH_FILE = os.path.join(BASE_DIR, "run.sh")
PROCESS_FILE = os.path.join(BASE_DIR, "process_org.py")

for path in (RUN_SH_FILE, PROCESS_FILE, DATA_FILE):
    assert os.path.isfile(path), f"Required file is missing or is not a regular file: {path}"
assert os.access(RUN_SH_FILE, os.X_OK), f"{RUN_SH_FILE} is not executable"
py_compile.compile(PROCESS_FILE, doraise=True)

with open(DATA_FILE, "rb") as f:
    original_data = f.read()


def execute_and_check(data, expected, label):
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f)

    try:
        os.remove(OUTPUT_FILE)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env.pop("DATA_DIR", None)
    result = subprocess.run(
        [RUN_SH_FILE],
        cwd=BASE_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"run.sh failed during {label} with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"run.sh did not create {OUTPUT_FILE} during {label}"
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert isinstance(actual, dict), f"summary.json must contain a JSON object during {label}"
    assert actual == expected, (
        f"Incorrect summary during {label}. Expected {expected}, got {actual}. "
        "Cycles, corrupted records, unreachable records, and concurrent updates must be handled correctly."
    )
    for key, value in actual.items():
        assert isinstance(key, str) and isinstance(value, int) and not isinstance(value, bool)


def make_random_case():
    token = secrets.token_hex(8)
    common = f"Shared-{token}"
    per_root = {root: f"Dept-{root}-{token}" for root in ("1", "6", "8")}
    data = {}
    expected = {common: 0}

    for root_index, root in enumerate(("1", "6", "8")):
        chain = [root] + [f"node-{root}-{token}-{i}" for i in range(1, 36)]
        expected[per_root[root]] = 0
        for i, employee_id in enumerate(chain):
            department = common if i % 2 == 0 else per_root[root]
            expected[department] += 1
            if i + 1 < len(chain):
                reports = [chain[i + 1]]
            else:
                reports = [chain[5]]  # A real reporting cycle.

            # Each worker also encounters a corrupted leaf. It must be skipped
            # without preventing the remaining valid chain from being processed.
            if i == 10:
                bad_id = f"corrupt-{root}-{token}"
                reports = [bad_id] + reports
                data[bad_id] = {"id": bad_id, "reports": []}

            data[employee_id] = {
                "id": employee_id,
                "department": department,
                "reports": reports,
            }

    # These records are not reachable from any configured root and must not be tallied.
    data[f"unreachable-{token}"] = {
        "id": f"unreachable-{token}",
        "department": f"Decoy-{token}",
        "reports": [],
    }
    return data, expected

error = None
try:
    generated_data, generated_expected = make_random_case()
    # Repetition exercises the concurrent update path rather than trusting one lucky run.
    for attempt in range(3):
        execute_and_check(generated_data, generated_expected, f"generated test run {attempt + 1}")
except BaseException as exc:
    error = exc
finally:
    try:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            restored_data = json.load(f)
        execute_and_check(
            restored_data,
            {"Engineering": 4, "Sales": 2, "Marketing": 2},
            "original organizational data",
        )
    except BaseException as exc:
        if error is None:
            error = exc
        else:
            error = AssertionError(f"{error}\nAdditionally, the original-data run failed: {exc}")

if error is not None:
    raise error
DYNAMIC_EOF

if ! python3 /tmp/test_dynamic_execution.py; then
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

BASE_DIR = "/home/user/ticket_8821"
OUTPUT_FILE = os.path.join(BASE_DIR, "output", "summary.json")
RUN_SH_FILE = os.path.join(BASE_DIR, "run.sh")
DATA_FILE = os.path.join(BASE_DIR, "data", "org.json")

def test_summary_json_exists():
    assert os.path.isfile(OUTPUT_FILE), (
        f"The output file {OUTPUT_FILE} was not found. "
        "Ensure the script runs successfully and generates the output."
    )

def test_summary_json_content():
    assert os.path.isfile(OUTPUT_FILE), "Cannot check content, output file is missing."

    with open(OUTPUT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_FILE} does not contain valid JSON.")

    expected_counts = {
        "Engineering": 4,
        "Sales": 2,
        "Marketing": 2
    }

    for dept, expected_count in expected_counts.items():
        assert dept in data, f"Department '{dept}' is missing from the output."
        assert data[dept] == expected_count, (
            f"Incorrect count for '{dept}'. Expected {expected_count}, got {data[dept]}. "
            "Ensure cycles are handled, corrupted records are skipped, and race conditions are fixed."
        )

    for dept in data:
        assert dept in expected_counts, f"Unexpected department '{dept}' found in the output."

def test_run_sh_fixed():
    assert os.path.isfile(RUN_SH_FILE), f"The file {RUN_SH_FILE} is missing."
    with open(RUN_SH_FILE, 'r') as f:
        content = f.read()
        assert "/tmp/wrong_data_path" not in content, (
            "The run.sh script still contains the incorrect DATA_DIR path."
        )
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
