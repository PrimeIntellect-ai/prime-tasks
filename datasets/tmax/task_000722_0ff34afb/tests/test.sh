#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
from collections import Counter

SCRIPT_PATH = "/home/user/fixed_process_logs.sh"


def run_script(log_path):
    return subprocess.run(
        [SCRIPT_PATH, log_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_bad_commit_txt():
    expected_file = "/tests/.expected_bad_commit.txt"
    actual_file = "/home/user/bad_commit.txt"

    assert os.path.isfile(expected_file), "Bad-commit oracle is unavailable to the verifier."
    assert os.path.isfile(actual_file), f"{actual_file} does not exist. You must write the bad commit SHA-1 to this file."

    with open(expected_file, "r") as f:
        expected_commit = f.read().strip()

    with open(actual_file, "r") as f:
        actual_commit = f.read().strip()

    assert actual_commit == expected_commit, f"The commit hash in {actual_file} is incorrect. Expected {expected_commit}, but got {actual_commit}."


def test_fixed_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."


def test_fixed_script_output_test_log():
    log_path = "/home/user/test_log.txt"
    result = run_script(log_path)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with return code {result.returncode}."

    output = result.stdout.strip()
    expected_output = "ERROR: 1\nINFO: 2\nWARN: 1"
    actual_lines = sorted(output.splitlines())
    expected_lines = sorted(expected_output.splitlines())

    assert actual_lines == expected_lines, f"Output from {SCRIPT_PATH} on {log_path} is incorrect.\nExpected:\n{expected_output}\nGot:\n{output}"


def test_fixed_script_output_edge_case():
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write("[2023-10-01 12:04:00] [DEBUG] [INFO] WARN ERROR\n")
        tmp_path = tmp.name

    try:
        result = run_script(tmp_path)
        assert result.returncode == 0, f"Running {SCRIPT_PATH} on edge case failed."

        output = result.stdout.strip()
        expected_output = "DEBUG: 1"
        assert output == expected_output, f"Output from {SCRIPT_PATH} on edge case is incorrect.\nExpected:\n{expected_output}\nGot:\n{output}"
    finally:
        os.remove(tmp_path)


def test_fixed_script_on_generated_logs():
    rng = random.SystemRandom()
    levels = ["INFO", "ERROR", "WARN", "DEBUG"]

    for case_number in range(4):
        actual_levels = levels[:] + [rng.choice(levels) for _ in range(28 + case_number)]
        rng.shuffle(actual_levels)
        expected_counts = Counter(actual_levels)

        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            for index, actual_level in enumerate(actual_levels):
                decoys = levels[:]
                rng.shuffle(decoys)
                nonce = rng.randrange(10**9, 10**10)
                message = (
                    f"message-{nonce} mentions {' '.join(decoys)} and contains "
                    f"[{rng.choice(levels)}] as message text"
                )
                tmp.write(
                    f"[2026-07-{(index % 28) + 1:02d} "
                    f"{index % 24:02d}:{index % 60:02d}:{(index * 7) % 60:02d}] "
                    f"[{actual_level}] {message}\n"
                )
            tmp_path = tmp.name

        try:
            result = run_script(tmp_path)
            assert result.returncode == 0, (
                f"Running {SCRIPT_PATH} on generated case {case_number} failed "
                f"with return code {result.returncode}."
            )
            actual_lines = sorted(result.stdout.strip().splitlines())
            expected_lines = sorted(
                f"{level}: {count}" for level, count in expected_counts.items()
            )
            assert actual_lines == expected_lines, (
                f"Output from {SCRIPT_PATH} on generated case {case_number} is incorrect.\n"
                f"Expected:\n{chr(10).join(expected_lines)}\n"
                f"Got:\n{result.stdout.strip()}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
