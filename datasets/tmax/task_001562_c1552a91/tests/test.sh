#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

REPORT_PATH = "/home/user/incident_report.txt"
PROJECT_DIR = "/home/user/data_processor"
RECOVERY_EXEC = os.path.join(PROJECT_DIR, "recovery")
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")
WAL_PATH = os.path.join(PROJECT_DIR, "system.wal")
CORE_PATH = os.path.join(PROJECT_DIR, "core.dump")

EXPECTED_REPORT_CONTENT = """SECRET_KEY: x9F2kL_pQ8zV1
LAST_TXN_ID: 7734190
DEADLOCK_HASH: A8F93B2C9E1045F1"""


def recover_key_from_git():
    result = subprocess.run(
        ["git", "-C", PROJECT_DIR, "log", "-p", "--all", "--", "config.h"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    matches = re.findall(r'WAL_SECRET\s*=\s*"([^"]+)"', result.stdout)
    assert matches, "Could not recover WAL_SECRET from git history."
    return matches[0]


def recover_hash_from_dump():
    with open(CORE_PATH, "rb") as f:
        data = f.read()
    match = re.search(rb"DEADLOCK_TX_HASH=([A-Za-z0-9]{16})", data)
    assert match, "Deadlock transaction hash was not found in the core dump."
    return match.group(1).decode("ascii")


def test_recovery_executable_built():
    assert os.path.isfile(RECOVERY_EXEC), "The 'recovery' executable was not built."
    assert os.access(RECOVERY_EXEC, os.X_OK), "The 'recovery' file is not executable."


def test_build_and_execute_recovery():
    assert os.path.isfile(BUILD_SCRIPT), "The build script is missing."
    assert os.path.isfile(WAL_PATH), "The WAL file is missing."

    # Require the repaired build process itself to successfully produce recovery.
    os.unlink(RECOVERY_EXEC)
    build = subprocess.run(
        ["bash", BUILD_SCRIPT],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"./build.sh failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(RECOVERY_EXEC), "./build.sh did not produce 'recovery'."
    assert os.access(RECOVERY_EXEC, os.X_OK), "The rebuilt recovery file is not executable."
    with open(RECOVERY_EXEC, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The recovery artifact is not a compiled executable."

    key = recover_key_from_git()
    run = subprocess.run(
        [RECOVERY_EXEC, key, WAL_PATH],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert run.returncode == 0, f"Recovery failed:\n{run.stdout}\n{run.stderr}"
    match = re.search(r"Last Committed TXN_ID=(\d+)", run.stdout)
    assert match, f"Recovery output did not report the last committed transaction ID: {run.stdout!r}"
    assert match.group(1) == "7734190", "Recovery reported the wrong last committed transaction ID."

    invalid = subprocess.run(
        [RECOVERY_EXEC, key + "_invalid", WAL_PATH],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert invalid.returncode != 0, "Recovery incorrectly accepted an invalid decryption key."


def test_incident_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Incident report not found at {REPORT_PATH}."


def test_incident_report_content():
    assert os.path.isfile(REPORT_PATH), f"Incident report not found at {REPORT_PATH}."
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_lines = EXPECTED_REPORT_CONTENT.splitlines()
    actual_lines = content.splitlines()

    assert len(actual_lines) >= 3, "Incident report does not have enough lines."
    assert actual_lines[0].strip() == expected_lines[0], f"Expected first line to be '{expected_lines[0]}', but got '{actual_lines[0]}'."
    assert actual_lines[1].strip() == expected_lines[1], f"Expected second line to be '{expected_lines[1]}', but got '{actual_lines[1]}'."
    assert actual_lines[2].strip() == expected_lines[2], f"Expected third line to be '{expected_lines[2]}', but got '{actual_lines[2]}'."

    # Also tie the report to values independently extracted during verification.
    assert actual_lines[0].strip() == f"SECRET_KEY: {recover_key_from_git()}"
    assert actual_lines[2].strip() == f"DEADLOCK_HASH: {recover_hash_from_dump()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
