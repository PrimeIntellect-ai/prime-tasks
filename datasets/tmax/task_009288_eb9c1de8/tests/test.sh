#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import sys
from collections import defaultdict


def compute_expected(logs):
    user_times = defaultdict(list)
    for entry in logs:
        user_times[entry["user"]].append(entry["time"])

    expected_blocked = set()
    for user, times in user_times.items():
        times.sort()
        for i in range(len(times) - 4):
            if times[i + 4] - times[i] <= 10:
                expected_blocked.add(user)
                break
    return sorted(expected_blocked)


def test_blocked_users_file():
    log_path = "/home/user/access_log.json"
    output_path = "/home/user/blocked_users.txt"
    script_path = "/home/user/check_rate.py"

    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    assert os.path.exists(output_path), f"Output file {output_path} is missing."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    # Recompute the expected blocked users for the supplied fixture.
    assert os.path.exists(log_path), f"Input file {log_path} is missing."
    with open(log_path, "r") as f:
        try:
            logs = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {log_path} is not valid JSON."

    expected_output = compute_expected(logs)

    with open(output_path, "r") as f:
        actual_lines = f.read().splitlines()

    actual_output = [line.strip() for line in actual_lines if line.strip()]
    assert actual_output == expected_output, (
        f"The contents of {output_path} are incorrect.\n"
        f"Expected: {expected_output}\n"
        f"Got: {actual_output}"
    )

    # Preserve the original files while exercising the submitted utility on
    # additional inputs whose expected answers are computed here.
    with open(log_path, "rb") as f:
        original_log = f.read()
    with open(output_path, "rb") as f:
        original_output = f.read()

    boundary_case = [
        {"user": "blocked_at_boundary", "time": t} for t in [10, 12, 14, 16, 20]
    ] + [
        {"user": "allowed_past_boundary", "time": t} for t in [30, 32, 34, 36, 41]
    ]

    unsorted_case = [
        {"user": "charlie", "time": 108},
        {"user": "alpha", "time": 1},
        {"user": "charlie", "time": 100},
        {"user": "bravo", "time": 50},
        {"user": "charlie", "time": 106},
        {"user": "alpha", "time": 40},
        {"user": "charlie", "time": 102},
        {"user": "bravo", "time": 70},
        {"user": "charlie", "time": 104},
        {"user": "alpha", "time": 80},
    ]

    token = secrets.token_hex(6)
    blocked_user = f"blocked_{token}"
    allowed_user = f"allowed_{token}"
    base = secrets.randbelow(100000) + 1000
    random_case = [
        {"user": blocked_user, "time": base + offset}
        for offset in [0, 1, 3, 7, 10, 100]
    ] + [
        {"user": allowed_user, "time": base + offset}
        for offset in [200, 203, 206, 209, 211]
    ] + [
        {"user": f"single_{token}_{i}", "time": base + 300 + i}
        for i in range(4)
    ]
    random.SystemRandom().shuffle(random_case)

    cases = [boundary_case, unsorted_case, random_case, []]

    try:
        for case_number, case in enumerate(cases, 1):
            expected = compute_expected(case)
            with open(log_path, "w") as f:
                json.dump(case, f)

            if os.path.lexists(output_path):
                os.unlink(output_path)

            result = subprocess.run(
                [sys.executable, script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"check_rate.py failed on behavioral case {case_number} with "
                f"exit code {result.returncode}.\nstdout: {result.stdout}\n"
                f"stderr: {result.stderr}"
            )
            assert os.path.exists(output_path), (
                f"check_rate.py did not create {output_path} on behavioral "
                f"case {case_number}."
            )
            assert os.path.isfile(output_path), f"{output_path} is not a file."

            with open(output_path, "r") as f:
                generated_lines = f.read().splitlines()
            generated = [line.strip() for line in generated_lines if line.strip()]
            assert generated == expected, (
                f"check_rate.py produced incorrect output on behavioral case "
                f"{case_number}.\nExpected: {expected}\nGot: {generated}"
            )
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        with open(output_path, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
