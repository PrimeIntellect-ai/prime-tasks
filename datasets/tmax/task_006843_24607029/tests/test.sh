#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess

def test_config_restored():
    config_path = "/home/user/build_project/config.inc"
    assert os.path.isfile(config_path), f"{config_path} was not restored to the correct location."

def test_report_content():
    report_path = "/home/user/debugging_report.txt"
    assert os.path.isfile(report_path), f"Diagnostic report {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "MISSING_ENV_VAR=ENABLE_STRICT_BUILD",
        "POISON_FILE=file_073.txt",
        "POISON_CONTENT=s/TARGET/UNCLOSED_REGEX"
    ]

    for expected in expected_lines:
        assert any(expected == line.strip() for line in content), f"Expected exact line '{expected}' missing from {report_path}."

def test_poison_file_removed():
    poison_path = "/home/user/build_project/src/file_073.txt"
    assert not os.path.exists(poison_path), f"The poison file {poison_path} is still in the src/ directory. It must be moved out."

def test_build_succeeds():
    build_script = "/home/user/build_project/build.sh"
    assert os.path.isfile(build_script), f"{build_script} is missing."

    env = os.environ.copy()
    env["ENABLE_STRICT_BUILD"] = "true"

    result = subprocess.run(
        ["./build.sh"],
        cwd="/home/user/build_project",
        env=env,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Build script failed to run successfully. Exit code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
