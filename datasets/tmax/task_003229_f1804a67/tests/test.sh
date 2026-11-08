#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import stat
import uuid
import secrets
import random
import subprocess
import pytest

ANALYZE_PATH = "/home/user/analyze.go"
JSON_PATH = "/home/user/department_stats.json"
USERS_CSV_PATH = "/home/user/data/users.csv"
ACTIVITY_LOG_PATH = "/home/user/data/activity.log"


def load_stats(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not a valid JSON file.")


def run_analyzer():
    try:
        result = subprocess.run(
            ["go", "run", ANALYZE_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Go program did not finish within 60 seconds.")

    assert result.returncode == 0, (
        "Running /home/user/analyze.go failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_go_program_generates_stats_for_runtime_inputs():
    assert os.path.exists(ANALYZE_PATH), f"Missing required Go program {ANALYZE_PATH}"
    assert stat.S_ISREG(os.lstat(ANALYZE_PATH).st_mode), f"{ANALYZE_PATH} must be a regular file"

    original_users = open(USERS_CSV_PATH, "rb").read()
    original_activity = open(ACTIVITY_LOG_PATH, "rb").read()

    departments = [f"Dept{secrets.token_hex(6)}" for _ in range(4)]
    user_ids = [str(uuid.uuid4()) for _ in range(4)]
    counts = [2 + secrets.randbelow(4), 1 + secrets.randbelow(4), 1 + secrets.randbelow(4), 0]
    expected_stats = {
        departments[i]: counts[i]
        for i in range(len(counts))
        if counts[i] > 0
    }

    try:
        with open(USERS_CSV_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["uuid", "username", "department"])
            for i, user_id in enumerate(user_ids):
                writer.writerow([user_id, f"user{i}", departments[i]])

        lines = [
            "[INFO] 2026-01-01 00:00:00 System started",
            f"[WARN] 2026-01-01 00:00:01 User<{uuid.uuid4()}> unknown user",
            "[ERROR] 2026-01-01 00:00:02 System message without a user",
        ]
        for i, count in enumerate(counts):
            for event_number in range(count):
                lines.append(
                    f"[INFO] 2026-01-01 00:01:{event_number:02d} "
                    f"User<{user_ids[i]}> generated event"
                )
        random.SystemRandom().shuffle(lines)
        with open(ACTIVITY_LOG_PATH, "wb") as f:
            f.write(("\n".join(lines) + "\n").encode("utf-16le"))

        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        run_analyzer()

        assert os.path.isfile(JSON_PATH), (
            f"File {JSON_PATH} does not exist after running the Go program."
        )
        actual_stats = load_stats(JSON_PATH)
        assert isinstance(actual_stats, dict), f"The root of {JSON_PATH} must be a JSON object (dictionary)."
        assert actual_stats == expected_stats, (
            "The Go program produced incorrect statistics for runtime-generated inputs.\n"
            f"Expected: {expected_stats}\n"
            f"Actual: {actual_stats}"
        )
    finally:
        with open(USERS_CSV_PATH, "wb") as f:
            f.write(original_users)
        with open(ACTIVITY_LOG_PATH, "wb") as f:
            f.write(original_activity)

    # Regenerate the required final artifact from the original source files.
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_analyzer()


def test_department_stats_json():
    json_path = "/home/user/department_stats.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist. The Go program must generate this file."

    # Parse the generated JSON
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            actual_stats = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {json_path} is not a valid JSON file.")

    assert isinstance(actual_stats, dict), f"The root of {json_path} must be a JSON object (dictionary)."

    # Recompute the expected stats from the source files
    users_csv_path = "/home/user/data/users.csv"
    activity_log_path = "/home/user/data/activity.log"

    assert os.path.isfile(users_csv_path), f"Missing source file {users_csv_path}"
    assert os.path.isfile(activity_log_path), f"Missing source file {activity_log_path}"

    # Load user mappings
    uuid_to_dept = {}
    with open(users_csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uuid_to_dept[row['uuid']] = row['department']

    # Parse activity log
    expected_stats = {}
    uuid_pattern = re.compile(r"User<([^>]+)>")
    with open(activity_log_path, 'r', encoding='utf-16le') as f:
        for line in f:
            match = uuid_pattern.search(line)
            if match:
                uuid_value = match.group(1)
                if uuid_value in uuid_to_dept:
                    dept = uuid_to_dept[uuid_value]
                    expected_stats[dept] = expected_stats.get(dept, 0) + 1

    # Compare actual with expected
    assert actual_stats == expected_stats, (
        f"The aggregated statistics in {json_path} do not match the expected values.\n"
        f"Expected: {expected_stats}\n"
        f"Actual: {actual_stats}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
