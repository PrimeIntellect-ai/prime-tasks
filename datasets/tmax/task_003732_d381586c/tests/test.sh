#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import subprocess
import tempfile

PROJECT_DIR = "/home/user/project"
CONFIG_FILE = os.path.join(PROJECT_DIR, "config.b64")
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")
BUILD_OUTPUT = os.path.join(PROJECT_DIR, "build_output.txt")


def run_script(script, cwd):
    result = subprocess.run(
        [script],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"build.sh exited with status {result.returncode}. stderr: {result.stderr!r}"
    )
    return result.stdout.strip()


def test_config_file_recovered():
    assert os.path.exists(CONFIG_FILE), f"Recovered config file {CONFIG_FILE} is missing."
    assert os.path.isfile(CONFIG_FILE), f"{CONFIG_FILE} is not a file."

    with open(CONFIG_FILE, "r") as f:
        content = f.read().strip()

    expected_content = "MTUgMjUgMzUgNDUgNTU="
    assert content == expected_content, f"Content of {CONFIG_FILE} is incorrect. Expected '{expected_content}', got '{content}'."


def test_build_output_correct():
    assert os.path.exists(BUILD_OUTPUT), f"Build output file {BUILD_OUTPUT} is missing."
    assert os.path.isfile(BUILD_OUTPUT), f"{BUILD_OUTPUT} is not a file."

    with open(BUILD_OUTPUT, "r") as f:
        content = f.read().strip()

    expected_score = "625"
    assert content == expected_score, f"Build output is incorrect. Expected '{expected_score}', got '{content}'."


def test_build_script_executes_and_computes_formula():
    assert os.path.exists(BUILD_SCRIPT), f"Build script {BUILD_SCRIPT} is missing."
    assert os.path.isfile(BUILD_SCRIPT), f"{BUILD_SCRIPT} is not a file."
    assert os.access(BUILD_SCRIPT, os.X_OK), f"{BUILD_SCRIPT} is not executable."

    actual = run_script(BUILD_SCRIPT, PROJECT_DIR)
    assert actual == "625", f"build.sh produced {actual!r} for the recovered config; expected '625'."

    for _ in range(4):
        values = [secrets.randbelow(500) + 1 for _ in range(5)]
        expected = sum(value * (index + 1) for index, value in enumerate(values))
        encoded = base64.b64encode(" ".join(map(str, values)).encode()).decode()

        with tempfile.TemporaryDirectory() as temp_dir:
            candidate = os.path.join(temp_dir, "build.sh")
            shutil.copy2(BUILD_SCRIPT, candidate)
            with open(os.path.join(temp_dir, "config.b64"), "w") as f:
                f.write(encoded)

            actual = run_script(candidate, temp_dir)
            assert actual == str(expected), (
                f"build.sh produced {actual!r} for decoded values {values}; "
                f"expected {expected}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
