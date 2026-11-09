#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/ticket_8841/sum_values.sh"
RESULT_PATH = "/home/user/ticket_8841/result.txt"
DATA_PATH = "/home/user/ticket_8841/data/"


def run_script(target, scale):
    env = os.environ.copy()
    env["MATH_SCALE"] = str(scale)
    return subprocess.run(
        [SCRIPT_PATH, target],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    ).stdout.strip()


def test_result_file_correct():
    assert os.path.isfile(RESULT_PATH), f"Result file missing: {RESULT_PATH}"

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert content == "770", f"Expected result to be '770', but got '{content}'"


def test_script_behavior_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"

    # Preserve the original spaces-in-names behavioral check.
    with tempfile.TemporaryDirectory() as temp_dir:
        spaces_dir = os.path.join(temp_dir, "test dir with spaces")
        os.makedirs(spaces_dir)

        file1 = os.path.join(spaces_dir, "file A.txt")
        file2 = os.path.join(spaces_dir, "fileB.txt")

        with open(file1, "w") as f:
            f.write("5\n")
        with open(file2, "w") as f:
            f.write("10\n")

        try:
            output = run_script(temp_dir, 3)
            assert output == "45", (
                "Script did not produce the correct output for test data. "
                f"Expected '45', got '{output}'"
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script execution failed: {e.stderr}")


def test_required_dataset_execution_matches_saved_result():
    output = run_script(DATA_PATH, 7)
    assert output == "770", f"Script returned '{output}' for the required data, expected '770'"
    with open(RESULT_PATH, "r") as f:
        saved = f.read().strip()
    assert saved == output, "result.txt does not match the script output for the required data"


def test_recursive_unusual_names_and_dynamic_math_scale():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(6)

    with tempfile.TemporaryDirectory() as base:
        target = os.path.join(base, f"target dir [odd] {token}")
        paths = [
            os.path.join(target, f"top file '{token}'.txt"),
            os.path.join(target, "nested dir with spaces", f"brackets [x] and star * {token}.txt"),
            os.path.join(target, "nested dir with spaces", f"line\nbreak {token}.txt"),
            os.path.join(target, "deep\tfolder", "another level", f"-leading-{token}.txt"),
        ]
        values = [rng.randint(11, 500) for _ in paths]

        for path, value in zip(paths, values):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(f"{value}\n")

        # Files that must not be included in the .txt sum.
        decoys = [
            os.path.join(target, "ignore me.log"),
            os.path.join(target, "nested dir with spaces", "ignore.txt.bak"),
            os.path.join(target, "deep\tfolder", "IGNORE.TXT"),
        ]
        for path in decoys:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write("999999\n")

        total = sum(values)
        scales = rng.sample(range(2, 20), 2)
        for scale in scales:
            expected = str(total * scale)
            output = run_script(target, scale)
            assert output == expected, (
                f"Expected {expected} for recursively discovered .txt files with "
                f"MATH_SCALE={scale}, got '{output}'"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
