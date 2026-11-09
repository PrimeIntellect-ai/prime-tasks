#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import stat
import subprocess
import pytest

PROCESS_PATH = "/home/user/process_math.py"
PIPELINE_PATH = "/home/user/run_pipeline.sh"
CSV_PATH = "/home/user/data/points.csv"
OUTPUT_PATH = "/home/user/output/grouped.json"
BACKUP_PATH = "/archive/remote_backup/grouped.json"


def load_json(path):
    assert os.path.isfile(path), f"Expected JSON file {path} was not created."
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")


def expected_groups(rows):
    result = {}
    for point_id, x, y, z in rows:
        distance = math.sqrt(x * x + y * y + z * z)
        key = str(math.floor(distance))
        result.setdefault(key, []).append(point_id)
    for ids in result.values():
        ids.sort()
    return result


def write_points(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "x", "y", "z"])
        writer.writerows(rows)


def run_as_user(command):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        capture_output=True,
        text=True,
    )


def test_process_math_script_exists():
    path = PROCESS_PATH
    assert os.path.isfile(path), f"Python script {path} does not exist."


def test_run_pipeline_script_exists_and_executable():
    path = PIPELINE_PATH
    assert os.path.isfile(path), f"Bash script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {path} is not executable."


def test_cron_schedule_content():
    path = "/home/user/cron_schedule.txt"
    assert os.path.isfile(path), f"Cron schedule file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert re.search(r"^30\s+2\s+\*\s+\*\s+\*", content, re.MULTILINE), f"Cron schedule {path} does not contain the correct time expression '30 2 * * *'."
    assert "/home/user/run_pipeline.sh" in content, f"Cron schedule {path} does not contain the command '/home/user/run_pipeline.sh'."

    # It must be exactly one system-crontab line and explicitly run as user.
    lines = content.splitlines()
    assert len(lines) == 1, f"Cron schedule {path} must contain exactly one line."
    assert re.fullmatch(
        r"30[ \t]+2[ \t]+\*[ \t]+\*[ \t]+\*[ \t]+user[ \t]+/home/user/run_pipeline\.sh",
        lines[0],
    ), "Cron entry must run /home/user/run_pipeline.sh as user at exactly 2:30 AM daily."


def test_pipeline_execution_and_output():
    # Preserve the original fixed-data execution and assertions.
    if os.path.exists(BACKUP_PATH):
        os.remove(BACKUP_PATH)

    result = subprocess.run([PIPELINE_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(BACKUP_PATH), f"Pipeline script did not create or copy the file to {BACKUP_PATH}."

    data = load_json(BACKUP_PATH)
    expected_data = {
        "0": [1, 6],
        "1": [2],
        "3": [3, 4, 5],
        "5": [8],
        "8": [7],
        "10": [9]
    }

    assert isinstance(data, dict), "JSON root must be a dictionary."
    expected_str_keys = {str(k): v for k, v in expected_data.items()}
    for k, v in expected_str_keys.items():
        assert k in data, f"Key '{k}' missing from JSON output."
        assert data[k] == v, f"Values for key '{k}' do not match. Expected {v}, got {data[k]}."
    for k in data.keys():
        assert k in expected_str_keys, f"Unexpected key '{k}' found in JSON output."


def test_process_math_and_pipeline_on_unseen_inputs():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    rng = random.SystemRandom()
    try:
        for trial in range(2):
            ids = rng.sample(range(20, 10000), 14)
            rows = []
            for point_id in ids:
                # Quarter-unit coordinates provide varied, nontrivial distances.
                coords = [rng.randint(-80, 80) / 4.0 for _ in range(3)]
                rows.append((point_id, coords[0], coords[1], coords[2]))
            rows.extend([
                (rng.randrange(10001, 20000), 0.0, 0.0, 0.0),
                (rng.randrange(20001, 30000), 3.0 + trial, 4.0, 0.0),
            ])
            rng.shuffle(rows)
            expected = expected_groups(rows)
            write_points(rows)

            # Exercise process_math.py directly so the pipeline cannot conceal a
            # hardcoded or nonfunctional mathematical-processing artifact.
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            result = run_as_user(["python3", PROCESS_PATH])
            assert result.returncode == 0, f"process_math.py failed on unseen input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
            assert load_json(OUTPUT_PATH) == expected, "process_math.py produced incorrect groups for unseen CSV data."

            # Exercise the complete pipeline on the same unseen input and verify
            # both the local result and copied backup.
            for path in (OUTPUT_PATH, BACKUP_PATH):
                if os.path.exists(path):
                    os.remove(path)
            result = run_as_user([PIPELINE_PATH])
            assert result.returncode == 0, f"Pipeline failed as user on unseen input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
            assert load_json(OUTPUT_PATH) == expected, "Pipeline produced incorrect local output for unseen CSV data."
            assert load_json(BACKUP_PATH) == expected, "Pipeline backup does not match the computed unseen-data result."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)


def test_pipeline_actually_executes_process_script_before_copying():
    with open(PROCESS_PATH, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(PROCESS_PATH).st_mode)
    marker = "/home/user/output/.pipeline_invoked_marker"
    payload = {"137": [901, 902]}
    stub = '''#!/usr/bin/env python3
import json
import os
os.makedirs("/home/user/output", exist_ok=True)
with open("/home/user/output/.pipeline_invoked_marker", "w") as f:
    f.write("invoked")
with open("/home/user/output/grouped.json", "w") as f:
    json.dump({"137": [901, 902]}, f)
'''

    try:
        with open(PROCESS_PATH, "w") as f:
            f.write(stub)
        os.chmod(PROCESS_PATH, 0o755)
        for path in (marker, OUTPUT_PATH, BACKUP_PATH):
            if os.path.exists(path):
                os.remove(path)

        result = run_as_user([PIPELINE_PATH])
        assert result.returncode == 0, f"Pipeline failed while checking orchestration.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        assert os.path.isfile(marker), "Pipeline did not execute /home/user/process_math.py."
        assert load_json(BACKUP_PATH) == payload, "Pipeline did not copy the result produced by process_math.py."
    finally:
        with open(PROCESS_PATH, "wb") as f:
            f.write(original_script)
        os.chmod(PROCESS_PATH, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
