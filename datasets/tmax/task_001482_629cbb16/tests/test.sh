#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

ANALYZER = "/home/user/analyzer"
LOG = "/home/user/system.log"
EXPECTED_ORIGINAL = "3000000000"


def run_analyzer(path, expected):
    proc = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"{path} exited with {proc.returncode}: {proc.stderr}"
    assert proc.stdout.strip() == str(expected), (
        f"Expected {expected} from {path}, but got {proc.stdout!r}"
    )


@pytest.fixture(scope="session")
def rebuilt_analyzer():
    fd, output_path = tempfile.mkstemp(prefix="rebuilt_analyzer_", dir="/tmp")
    os.close(fd)
    os.unlink(output_path)
    proc = subprocess.run(
        ["g++", "-std=c++17", "/home/user/analyzer.cpp", "/home/user/utils.cpp", "-o", output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"The repaired C++ sources do not compile/link:\n{proc.stderr}"
    try:
        yield output_path
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)


def test_executable_exists():
    executable_path = "/home/user/analyzer"
    assert os.path.isfile(executable_path), f"Executable not found at {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File at {executable_path} is not executable"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {executable_path} is not a compiled executable"


def test_result_file():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Result file not found at {result_path}"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_result = "3000000000"
    assert content == expected_result, f"Expected result to be {expected_result}, but got {content}"


def test_analyzers_on_original_log(rebuilt_analyzer):
    run_analyzer(ANALYZER, EXPECTED_ORIGINAL)
    run_analyzer(rebuilt_analyzer, EXPECTED_ORIGINAL)


def test_analyzers_handle_unpredictable_large_totals(rebuilt_analyzer):
    backup = LOG + ".verifier_backup_" + secrets.token_hex(8)
    os.replace(LOG, backup)
    try:
        for _ in range(3):
            values = [2_000_000_000, 1_500_000_000]
            values.extend(secrets.randbelow(2_000_000_001) for _ in range(12))
            expected = sum(values)

            for executable in (ANALYZER, rebuilt_analyzer):
                with open(LOG, "w") as f:
                    for i, value in enumerate(values):
                        f.write(f'10.0.0.{i} - - [11/Sep/2026:00:00:00 +0000] "GET /{i} HTTP/1.0" 200 {value}\n')
                run_analyzer(executable, expected)
    finally:
        if os.path.exists(LOG):
            os.unlink(LOG)
        os.replace(backup, LOG)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
