#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

CRASH_FILE = "/home/user/project/fuzz_crash.bin"
ORIGINAL_CRASH_FILE = "/tests/fuzz_crash.bin"


def assert_crash_dump_unchanged():
    assert os.path.isfile(CRASH_FILE), f"{CRASH_FILE} is missing"
    assert os.path.isfile(ORIGINAL_CRASH_FILE), f"Trusted crash dump {ORIGINAL_CRASH_FILE} is missing"

    with open(CRASH_FILE, "rb") as f:
        current_data = f.read()
    with open(ORIGINAL_CRASH_FILE, "rb") as f:
        original_data = f.read()

    assert current_data == original_data, "fuzz_crash.bin was modified"
    return current_data


def get_expected_key():
    data = assert_crash_dump_unchanged()
    match = re.search(b"APP_SECRET_KEY=([0-9a-fA-F]{32})", data)
    assert match is not None, "Could not find APP_SECRET_KEY in fuzz_crash.bin"
    return match.group(1).decode("ascii")


def test_crash_dump_unchanged():
    assert_crash_dump_unchanged()


def test_recovered_key_file():
    expected_key = get_expected_key()
    key_file = "/home/user/recovered_key.txt"

    assert os.path.isfile(key_file), f"{key_file} is missing"

    with open(key_file, "r") as f:
        content = f.read().strip()

    assert content == expected_key, f"Expected key '{expected_key}', but found '{content}' in {key_file}"


def test_cargo_build_succeeds():
    project_dir = "/home/user/project"
    assert os.path.isdir(project_dir), f"{project_dir} is missing"

    result = subprocess.run(
        ["cargo", "build"],
        cwd=project_dir,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"cargo build failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
